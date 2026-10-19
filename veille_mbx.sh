#!/bin/bash
# veille_mbx.sh [boîte] [secondes] — veille LÉGÈRE d'une boîte MBX (relais de pxl-tx, :8720), pour CETTE VM.
#
#   bash veille_mbx.sh pxl-switcher 6900      # en tâche de fond SUIVIE (run_in_background, timeout 7100000)
#
# ─── Pourquoi (15/10) ─────────────────────────────────────────────────────────
# Eliott, via turbohq puis en direct : rester à l'écoute de MBX même quand personne ne parle à la session. La boîte
# pxl-switcher a accumulé 51 messages : je ne la lisais qu'en `--peek` (rien n'était jamais marqué lu) et seulement
# quand on me parlait — le redémarrage de test de mire-diag de 13:35 UTC, annoncé pour que j'y capture le tube, est
# passé sans moi.
# Même logique que `PXL-TurboHQ/deploy/claudevm/veille_mbx.sh` (le dispositif de turbohq), sur le chemin de CETTE VM :
# `ssh pxl-tx` (ProxyCommand `tailscale nc`), pas leurs `tx_ssh.py`/`tunnel_assure.sh`.
#
# ─── Ce qu'il fait ────────────────────────────────────────────────────────────
# (Jusqu'au 17/10 au soir : toutes les 60 s, côté carte depuis le 16/10, UN curl de l'annuaire (`/api/turbohq/mbx`, lecture seule) — jamais `mbx.js who`, qui lance un Node
# complet à chaque appel (la carte voyait « des sessions SSH courtes s'enchaîner », 15/10). Depuis : la SONNETTE, voir
# la boucle de la carte.) Dès qu'un message attend :
# `mbx.js read` (la boîte se VIDE), on l'imprime et on SORT — la fin de la tâche réveille la session, qui traite puis
# RÉARME. Au terme de la fenêtre (6900 s, sous le plafond de 2 h d'une tâche de fond) : « fin de fenêtre », à réarmer.
# ⭐ Il écrit un TÉMOIN DE VIE à chaque tour (`/tmp/veille-mbx.vivant`, l'heure) : c'est ce que lit la tâche planifiée
# horaire pour savoir s'il tourne — `pgrep -f` se trouverait lui-même dans la ligne de commande qui le cherche.
# ⚠️ Ce n'est que la moitié : quand le conteneur est recyclé, la veille meurt avec lui. L'autre moitié est la tâche
# planifiée horaire de la session (« Veille MBX pxl-switcher »).
#
# ─── UNE SEULE SESSION SSH, PAS UNE PAR MINUTE (16/10, § 255.15 du DOSSIER_RGA de PXL-Switcher) ─────────────────
# La première version ouvrait une session `ssh pxl-tx` À CHAQUE TOUR : côté carte, un `tailscaled be-child` et un scope
# systemd (session-cNNNNN.scope) par minute, et par veille — trois veilles tournaient (la mienne, turbonode,
# claudevm-vps), soit ~60 sessions/heure. Or l'entrée HDMI de pxl-tx perd ~45 ms d'IRQ de temps en temps, et l'IRQ du
# récepteur est épinglée au CPU5 ; un scope systemd est né 23 ms avant le trou de 19:53:25 UTC (1 cas sur 3, aucune
# preuve). Pour que la question se tranche, les veilles cessent toutes d'en ouvrir : la boucle tourne CÔTÉ CARTE, dans
# une session qui dure toute la fenêtre, et rend une ligne « TIC » par minute (le témoin de vie local suit ces lignes).
# Une session coupée (tunnel tombé : ServerAlive la ferme en ~90 s) est rouverte, et le tunnel relevé au 3e échec.
BOITE="${1:-pxl-switcher}"; FENETRE="${2:-6900}"
ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
U=http://127.0.0.1:8720
M=/home/radxa/turbohq/pxl-turbohq-client/bin/mbx.js
VIVANT=/tmp/veille-mbx.vivant
# Heure du journal en HEURE FRANÇAISE, fuseau écrit (règle d'Eliott du 18/10 : jamais une heure nue en UTC) ; le
# témoin de vie reste un epoch, qui n'a pas de fuseau.
heure() { TZ=Europe/Paris date '+%H:%M:%S %Z'; }
remonter() { TS_DIR="$ICI/.tailscale" timeout 120 bash "$ICI/tunnel_up.sh" 8710 >/dev/null 2>&1; }

# La boucle de la carte : arguments = relais, mbx.js, boîte, secondes restantes.
# LA SONNETTE (17/10 au soir, même version que turbohq 5b423aa) : plus de relevé toutes les 60 s. On s'abonne au flux SSE
# de la boîte (`/api/turbohq/mbx/<boîte>/stream` : le relais y pousse chaque message à l'instant, et `: ping` toutes
# les 15 s), PUIS on lit l'annuaire 0,5 s après — un message tombé entre les deux est vu par l'un ou par l'autre, jamais
# par aucun. Le flux ne VIDE rien (le `read` seul vide). Une ligne « TIC » par ligne non vide du flux (≤ 15 s) : le
# témoin de vie local suit. Flux muet 50 s, ou fini (10 min au plus) : on se réabonne, dans la MÊME session SSH.
BOUCLE_CARTE='U=$1; M=$2; B=$3; fin=$(( $(date +%s) + $4 ))
courrier() { echo "COURRIER $1"; MBX_URL=$U timeout 15 node "$M" --as "$B" read 2>&1; echo "FIN-COURRIER"; exit 0; }
while :; do
  r=$(( fin - $(date +%s) )); [ "$r" -gt 600 ] && r=600; [ "$r" -lt 5 ] && break
  exec 3< <(curl -sN -m "$r" --speed-time 45 --speed-limit 1 "$U/api/turbohq/mbx/$B/stream" 2>/dev/null; echo FLUX-FIN)
  p=$!; sleep 0.5
  n=$(curl -s -m 5 "$U/api/turbohq/mbx" | python3 -I -c "
import sys, json
try: print(next((b.get(\"queued\", 0) for b in json.load(sys.stdin) if b.get(\"name\") == sys.argv[1]), 0))
except Exception: pass" "$B")
  echo "TIC ${n:-?}"
  if [ -n "$n" ] && [ "$n" -gt 0 ]; then pkill -P "$p" curl; courrier "$n"; fi
  while IFS= read -r -t 50 -u 3 l; do
    case "$l" in
      "data: "*) pkill -P "$p" curl; courrier 1 ;;
      FLUX-FIN) break ;;
      "") ;;
      *) echo "TIC" ;;
    esac
  done
  pkill -P "$p" curl 2>/dev/null; exec 3<&-
done
echo "FIN-FENETRE"'


fin=$(( $(date +%s) + FENETRE )); echecs=0
while [ "$(date +%s)" -lt $fin ]; do
  date -u +%s > "$VIVANT"
  etat=rien
  while IFS= read -r l; do
    l=${l%$'\r'}
    case $etat in
      courrier) [ "$l" = FIN-COURRIER ] && { rm -f "$VIVANT"; exit 0; }; echo "$l" ;;
      *) case $l in
           "TIC ?") ;;                                                 # relais muet ce tour-ci : la session vit
           TIC*) date -u +%s > "$VIVANT"; echecs=0 ;;
           COURRIER*) echo "$(heure) [veille] ${l#COURRIER } message(s) pour $BOITE :"; etat=courrier ;;
           FIN-FENETRE) etat=fini ;;
         esac ;;
    esac
  done < <(ssh -o ConnectTimeout=20 -o BatchMode=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 pxl-tx \
             bash -s -- "$U" "$M" "$BOITE" "$(( fin - $(date +%s) ))" <<<"$BOUCLE_CARTE" 2>/dev/null)
  [ $etat = courrier ] && { rm -f "$VIVANT"; exit 0; }                  # session coupée en pleine lecture : on rend ce qu'on a
  [ $etat = fini ] && break
  echecs=$((echecs + 1))                                                # session tombée avant la fin de la fenêtre
  [ $echecs = 3 ] && remonter                                           # tunnel tombé : on le relève
  [ $echecs = 10 ] && echo "$(heure) [veille] pxl-tx injoignable depuis ~10 essais"
  sleep 20
done
rm -f "$VIVANT"
echo "$(heure) [veille] fin de fenêtre, rien reçu"
