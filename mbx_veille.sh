#!/usr/bin/env bash
# Veille sur une boîte MBX — le courrier de la tour, sans le perdre et sans y
# repenser.
#
#   bash mbx_veille.sh [boîte] [pair] [minutes]     # défauts : switch-dev · claudevm-turbohq · 50
#
# ⚠️ À lancer en TÂCHE HARNAIS (`run_in_background` de l'outil Bash), JAMAIS en
# `nohup` détaché : le recyclage tue un détaché en vol, alors qu'une tâche
# suivie **réveille la session quand elle se termine** — et c'est tout le
# mécanisme. Le script sort dès qu'il y a du courrier ; sa sortie EST la
# notification. (Le garde-fou des labos, nuit du 19-20/08 : « une mort du
# process réveille la session ».)
#
# ─── Les trois règles, et chacune vient d'un défaut payé ──────────────────────
#
# 1. 🔴 **On PEEK, on ne draine JAMAIS.** Le drain vide la boîte : si la VM meurt
#    entre la lecture et le traitement, le message est perdu et personne ne le
#    sait. La boîte de la tour est la source de vérité et elle survit à cette
#    VM — le drain est un geste CONSCIENT, au moment où on traite. C'est la même
#    correction que les curseurs de MBX v2 (MBX_V2_BRIEF §4).
#
# 2. 🔴🔴 **« Vivant » ne veut pas dire « fonctionnel » — on teste la FONCTION.**
#    Mesuré trois fois en une heure le 22/08 : un nœud tailscale « déjà
#    authentifié » qui était `Online:False` · un pont dont le processus vivait
#    pendant que `tailscaled` était mort · un `tailscaled` vivant avec une
#    socket périmée. `pgrep` répond « oui » dans les trois cas. Ici, la seule
#    question posée est *« est-ce que le courrier arrive ? »* — une requête, pas
#    une liste de processus.
#
# 3. ⏳ **Il est BORNÉ, et c'est volontaire.** Un veilleur éternel n'existe pas :
#    la VM est recyclée. Au bout de `minutes` il rend la main **en le disant** —
#    ce qui réveille la session, qui le relance. Un veilleur qu'on croit vivant
#    est pire qu'un veilleur absent (leçon de la nuit : « un banc qui doit durer
#    se relance, il ne se suppose pas vivant »).
#
# ⚠️ Le tailnet n'est routable NI par curl NI par le proxy d'agent (userspace
# networking) : la seule voie est `tailscale nc`, d'où le pont TCP local. Il se
# remonte tout seul ici — il meurt avec la VM.
set -uo pipefail

BOITE=${1:-${MBX_AS:-switch-dev}}
PAIR=${2:-${MBX_PAIR:-claudevm-turbohq}}
MINUTES=${3:-50}
PORT=${MBX_PONT_PORT:-8099}
PAUSE=${MBX_PAUSE:-20}
ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TS="$ICI/.tailscale/tailscale"
SOCK="$ICI/.tailscale/ts.sock"
# 🔴 Sur DISQUE, jamais en mémoire : c'est ce qui a rendu le post-mortem de la
# nuit du 19-20/08 possible (les sondes .idx ont survécu, pas les processus).
JOURNAL=${MBX_JOURNAL:-/tmp/pxl-mbx/veille-$BOITE.log}
mkdir -p "$(dirname "$JOURNAL")"

dire() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*" | tee -a "$JOURNAL"; }

# ⭐⭐ **LE CONTRÔLE QUE LA VEILLE PORTE ELLE-MÊME** (22/08, après avoir tourné
# aveugle au-dessus de cinq messages). Il n'interroge aucun réseau : il donne au
# COMPTEUR trois charges dont on connaît la réponse, et vérifie qu'il les
# distingue. Un banc sans contrôle intégré ne se trompe pas moins — il se trompe
# sans le dire.
#   bash mbx_veille.sh --controle
compter() {
  node -e '
    let s=""; process.stdin.on("data",d=>s+=d).on("end",()=>{
      try {
        const j = JSON.parse(s);
        const a = Array.isArray(j) ? j : (j.messages ?? j.msgs ?? null);
        process.stdout.write(Array.isArray(a) ? String(a.length) : "-1");
      } catch { process.stdout.write("-1"); } });' 2>/dev/null
}
if [ "${1:-}" = "--controle" ]; then
  ec=0
  essai() {   # nom · charge · attendu
    r=$(printf '%s' "$2" | compter)
    if [ "$r" = "$3" ]; then printf '✔ %s → %s\n' "$1" "$r"
    else printf '✗ %s → %s (attendu %s)\n' "$1" "$r" "$3"; ec=1; fi
  }
  # 🔴 La forme RÉELLE de la boîte : un tableau NU. C'est celle que la première
  #    version ne savait pas lire, et c'est donc le premier essai.
  essai 'tableau nu de 2 messages' '[{"from":"a","text":"x"},{"from":"b","text":"y"}]' 2
  essai 'boîte vide'               '[]'                                                0
  essai 'objet {messages:[…]}'     '{"messages":[{"from":"a"}]}'                       1
  # ⚠️ Et les deux formes d'IGNORANCE, qui ne doivent JAMAIS passer pour un zéro.
  essai 'JSON illisible'           'Invalid channel name'                             -1
  essai 'forme inconnue'           '{"ok":true}'                                      -1
  exit "$ec"
fi

[ -x "$TS" ] || { dire "🔴 tailscale absent ($TS) — lancer tunnel_up.sh d'abord"; exit 0; }

# ── Le pair, résolu par NOM. Une IP en dur périme au prochain enregistrement ;
#    le nom, lui, est ce qu'un humain écrit dans un ordre.
ip_du_pair() {
  "$TS" --socket="$SOCK" status 2>/dev/null \
    | awk -v n="$PAIR" '$2 == n {print $1; exit}'
}

# ── Le pont : on le juge sur ce qu'il RELAIE, pas sur son existence (règle 2).
pont_repond() {
  curl -s --noproxy '*' --max-time 12 \
    "http://127.0.0.1:$PORT/api/turbohq/mbx/who" 2>/dev/null | grep -q '.'
}

monter_pont() {
  local ip; ip=$(ip_du_pair)
  [ -n "$ip" ] || { dire "⚠️ pair « $PAIR » introuvable au tailnet (hors ligne ?)"; return 1; }
  # ⚠️ `pkill -f pont.mjs` tue le shell qui l'appelle : son propre motif est dans
  # sa ligne de commande. On tue par PID, jamais par motif large.
  ps -eo pid,args | awk '/[m]bx-pont\.mjs/ {print $1}' | while read -r p; do kill "$p" 2>/dev/null; done
  cat > /tmp/pxl-mbx/mbx-pont.mjs <<'JS'
import { createServer } from 'node:net';
import { spawn } from 'node:child_process';
const [TS, SOCK, IP, PORT, LOCAL] = process.argv.slice(2);
createServer((c) => {
  const n = spawn(TS, [`--socket=${SOCK}`, 'nc', IP, PORT]);
  c.pipe(n.stdin); n.stdout.pipe(c);
  const fin = () => { try { n.kill(); } catch {} try { c.destroy(); } catch {} };
  c.on('error', fin); c.on('close', fin); n.on('exit', fin);
}).listen(Number(LOCAL), '127.0.0.1');
JS
  setsid node /tmp/pxl-mbx/mbx-pont.mjs "$TS" "$SOCK" "$ip" 8080 "$PORT" \
    >> /tmp/pxl-mbx/pont.log 2>&1 &
  sleep 3
  pont_repond && { dire "pont → $PAIR ($ip:8080) sur 127.0.0.1:$PORT"; return 0; }
  dire "⚠️ pont monté mais muet — $PAIR ne répond pas sur 8080"
  return 1
}

dire "veille sur « $BOITE » chez « $PAIR » — peek toutes les ${PAUSE}s, borne ${MINUTES} min"
FIN=$(( $(date +%s) + MINUTES * 60 ))

while [ "$(date +%s)" -lt "$FIN" ]; do
  if ! pont_repond && ! monter_pont; then sleep "$PAUSE"; continue; fi

  # 🔴 PEEK : pas de `?drain=1`. Rien n'est consommé ici.
  REP=$(curl -s --noproxy '*' --max-time 15 \
        "http://127.0.0.1:$PORT/api/turbohq/mbx/$BOITE" 2>/dev/null)
  # 🔴🔴 **LA BOÎTE REND UN TABLEAU NU, ET LA PREMIÈRE VERSION CHERCHAIT UN
  # OBJET** (`j.messages ?? j.msgs ?? []`). Mesuré le 22/08 : la veille a tourné
  # au-dessus de **cinq** messages — dont un d'Eliott qui nous appelait — en
  # rendant 0 à chaque tour. *Une veille qui ne peut pas voir son sujet ne dit
  # pas « je ne vois rien », elle dit « il n'y a rien ».*
  # ⭐ La forme se **MESURE** (`curl … | node -e 'JSON.parse'`), elle ne se
  # suppose pas — c'est la règle du dépôt d'à côté : *un témoin qui confirme
  # l'hypothèse de celui qui l'a écrit ne prouve rien.*
  # ⚠️ Et on distingue désormais **« zéro message »** de **« je ne sais pas
  # lire »** : sans ça, un changement de forme côté relais rendrait la veille
  # muette pour toujours, et le silence se lirait comme une bonne nouvelle.
  # ⚠️ **UN SEUL compteur**, celui que `--controle` met à l'épreuve. Le recopier
  # ici en ferait deux, et le contrôle ne prouverait plus rien de la boucle.
  N=$(printf '%s' "$REP" | compter)

  if [ "${N:-0}" = "-1" ]; then
    dire "🔴 « $BOITE » a répondu quelque chose d'ILLISIBLE — la veille ne peut RIEN voir."
    dire "   Forme attendue : un TABLEAU JSON de messages. Reçu (200 premiers octets) :"
    dire "   ${REP:0:200}"
    printf '%s\n' "$REP" >> "$JOURNAL"
    exit 0                      # aveugle ⇒ on réveille la session, on ne veille pas dans le vide
  fi

  if [ "${N:-0}" -gt 0 ] 2>/dev/null; then
    dire "📬 $N message(s) dans « $BOITE » — la boîte n'est PAS vidée, drainer au traitement :"
    dire "   curl -s --noproxy '*' 'http://127.0.0.1:$PORT/api/turbohq/mbx/$BOITE?drain=1'"
    printf '%s\n' "$REP" >> "$JOURNAL"
    exit 0                      # ⭐ la SORTIE est la notification : la session se réveille
  fi
  sleep "$PAUSE"
done

dire "borne atteinte (${MINUTES} min) sans courrier — relancer la veille."
exit 0
