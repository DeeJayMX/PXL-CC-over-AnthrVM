#!/usr/bin/env bash
# Remonte le tunnel Tailscale dans une VM neuve, sans auth interactive.
#
#   bash tunnel_up.sh [port]        # défaut : 8710, la console PXL Switch
#
# ─── Ce que ce script résout, et ce qu'il ne peut pas résoudre ────────────────
#
# 🔴 **La clé de nœud Tailscale ne peut PAS être rendue persistante.** Deux murs,
# et aucun des deux ne se contourne par du code :
#
#   1. Le `statedir` de tailscaled vit dans le workdir de la VM. La VM est
#      recyclée (§2 du dossier) : au réveil suivant, l'état a disparu avec elle.
#   2. Le versionner serait pire que le perdre. `tailscaled.state` contient la
#      **clé privée du nœud** ; la pousser sur GitHub, c'est publier de quoi se
#      faire passer pour cette machine sur le tailnet. Un dépôt n'est pas un
#      coffre, et celui-ci est de surcroît destiné à être lu.
#
# ⭐ Ce qui PEUT être persistant, c'est la **clé d'authentification**, dans les
# variables d'environnement de l'environnement Claude Code — le seul endroit du
# dispositif qui survive à un recyclage sans être un dépôt git.
#
#   Où la poser : claude.ai/code → l'icône **nuage** dans la rangée AU-DESSUS de
#                 la zone de saisie (il n'y a ni page de réglages ni URL directe,
#                 c'est pour ça qu'on la cherche) → roue dentée → Environment
#                 variables, au format .env :  TS_AUTHKEY=tskey-auth-…
#   ⚠️ Effet     : les valeurs sont copiées au DÉMARRAGE d'une session. Une
#                 modification n'atteint que les sessions ouvertes ensuite.
#
# 🔴 **Ce n'est PAS un coffre à secrets, et la doc l'interdit explicitement** :
# « no dedicated secrets store, so don't add API keys or other credentials ».
# Quiconque utilise l'environnement lit les valeurs. Il n'existe aucun endroit
# sûr ici — ni cette boîte, ni le setup script, ni ce dépôt. La bonne question
# n'est donc pas où la cacher, mais comment rendre sa fuite sans conséquence.
#
# ⇒ Générer la clé **réutilisable + ÉPHÉMÈRE + TAGUÉE** (Tailscale admin →
#   Settings → Keys), avec une ACL qui borne le tag. Réutilisable, sinon elle ne
#   sert qu'une session ; éphémère, pour que le nœud s'efface en se déconnectant
#   et qu'une clé volée ne donne qu'un nœud qui s'évapore ; taguée, pour qu'elle
#   n'ouvre pas le tailnet. ⚠️ 90 jours est le plafond Tailscale : elle expirera,
#   et ce script le dira clairement le jour venu plutôt que d'échouer en silence.
#
# ⚠️ Sur un compte Pro/Max une session partagée est PUBLIQUE. Ce script
# n'affiche jamais la clé et ne l'écrit jamais sur le disque — ne pas défaire ça,
# et ne jamais demander à une session d'afficher $TS_AUTHKEY.
#
# ⚠️ En revanche la clé PASSE bien par la ligne de commande, et il faut le dire
# plutôt que le maquiller : `tailscale up` ne lit pas `TS_AUTHKEY` dans son
# environnement — `--auth-key` est la seule entrée (mesuré sur 1.98.10, `up
# --help`). La seule alternative offerte est `--auth-key=file:/chemin`, qui
# l'écrit sur le disque : ce n'est pas mieux, c'est pire. Elle est donc visible
# dans `/proc/<pid>/cmdline` le temps de l'appel. Mesuré ici : la VM tourne en
# uid 0 et `/proc/self/environ` est en 0400 — un seul utilisateur, donc la même
# frontière de confiance de toute façon. 🔴 Sur une machine PARTAGÉE, ce
# raisonnement tombe : n'y lancez pas ce script tel quel.
#
# ─── Deux pièges déjà payés, gardés ici pour ne pas les repayer ───────────────
#
# ⚠️ `--statedir` (un RÉPERTOIRE), jamais `--state` (un fichier). Sans var root,
#    tailscaled n'a nulle part où ranger son certificat et Funnel répond 503 en
#    boucle avec « no TailscaleVarRoot » dans le journal. Une demi-heure.
#
# ⚠️ `serve`, PAS `funnel`. `serve` publie sur le tailnet seul ; `funnel` ouvre
#    sur l'internet public. L'exposition publique a été coupée sur décision
#    d'Eliott le 02/08/2026, et une console d'antenne ne doit jamais se rouvrir
#    au monde par un effet de bord de redémarrage. Si un jour Funnel est
#    volontairement remis, que ce soit une ligne écrite exprès, pas ce défaut-ci.
#
# Rappel du §3 bis : l'egress est restreint à TCP/80, TCP/443 et UDP/53.
# Tailscale ne passe donc qu'en **relais DERP**, jamais en direct. C'est plus
# lent et parfaitement suffisant pour une surface web.
set -uo pipefail

PORT=${1:-8710}
DIR=${TS_DIR:-"$(pwd)/.tailscale"}
VERSION=${TS_VERSION:-1.98.10}
mkdir -p "$DIR"

log() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }
die() { printf '\n🔴 %s\n' "$*" >&2; exit 1; }

# ── 1. La clé. On échoue ICI, tout de suite, avec la marche à suivre.
if [ -z "${TS_AUTHKEY:-}" ]; then
  die "TS_AUTHKEY absent de l'environnement.

    Où le poser — ce n'est PAS dans une page de réglages :
      claude.ai/code → icône nuage AU-DESSUS de la zone de saisie
                     → roue dentée → Environment variables
      TS_AUTHKEY=tskey-auth-…

    Générer la clé réutilisable + ÉPHÉMÈRE + TAGUÉE : cette boîte n'est pas un
    coffre, ses valeurs sont lisibles par quiconque utilise l'environnement.
    Voir l'en-tête de ce fichier."
fi

# ── 2. Les binaires. Absents d'une VM neuve : on les retire par TCP/443.
if [ ! -x "$DIR/tailscaled" ]; then
  log "binaires absents, téléchargement de Tailscale $VERSION"
  ARCH=$(uname -m); case "$ARCH" in x86_64) ARCH=amd64 ;; aarch64) ARCH=arm64 ;; esac
  curl -fsSL "https://pkgs.tailscale.com/stable/tailscale_${VERSION}_${ARCH}.tgz" \
    -o "$DIR/ts.tgz" || die "téléchargement impossible — vérifier \$HTTPS_PROXY/__agentproxy/status"
  tar -xzf "$DIR/ts.tgz" -C "$DIR" --strip-components=1 \
    "tailscale_${VERSION}_${ARCH}/tailscale" "tailscale_${VERSION}_${ARCH}/tailscaled" \
    || die "archive illisible"
  chmod +x "$DIR/tailscale" "$DIR/tailscaled"
fi

TS="$DIR/tailscale --socket=$DIR/ts.sock"

# ── 3. Le démon. Idempotent : on ne relance pas ce qui tourne déjà.
if ! pgrep -f "tailscaled --tun=userspace-networking" > /dev/null 2>&1; then
  log "démarrage de tailscaled (userspace, statedir)"
  # `--tun=userspace-networking` : pas de /dev/net/tun dans le conteneur.
  "$DIR/tailscaled" --tun=userspace-networking \
    --statedir="$DIR/var" --socket="$DIR/ts.sock" >> "$DIR/tailscaled.log" 2>&1 &
  for _ in $(seq 1 20); do [ -S "$DIR/ts.sock" ] && break; sleep 1; done
  [ -S "$DIR/ts.sock" ] || die "tailscaled n'a pas ouvert sa socket — voir $DIR/tailscaled.log"
else
  log "tailscaled tourne déjà"
fi

# ── 4. L'authentification. ⚠️ `--auth-key` est la SEULE entrée : `tailscale up`
#      ne lit pas TS_AUTHKEY dans son environnement (mesuré, 1.98.10). Voir
#      l'en-tête pour ce que ça expose et pourquoi c'est accepté ici.
if $TS status > /dev/null 2>&1; then
  log "nœud déjà authentifié"
else
  log "authentification par clé (relais DERP — l'egress interdit le direct)"
  if ! timeout 90 "$DIR/tailscale" --socket="$DIR/ts.sock" up \
       --auth-key="$TS_AUTHKEY" --hostname="${TS_HOSTNAME:-pxl-console}" \
       --accept-dns=false >> "$DIR/tailscaled.log" 2>&1; then
    die "authentification refusée.

    La cause la plus probable est une clé EXPIRÉE — Tailscale les plafonne à
    90 jours — ou à usage unique déjà consommée. En régénérer une réutilisable
    et la reposer dans TS_AUTHKEY. Détail : $DIR/tailscaled.log"
  fi
fi

# ── 4 bis. 🔴 LE RELAIS HOME, et c'est LA correction qui a coûté une matinée.
#
# La VM est hébergée aux États-Unis : son `netcheck` ne sonde que des régions
# américaines et elle choisit `nyc` comme relais home. Les pairs qui veulent la
# joindre SANS SOLLICITATION envoient vers ce relais — et le trafic n'arrive
# jamais. Le sens sortant, lui, marche : c'est nous qui ouvrons la connexion vers
# la région du pair, et les réponses reviennent dessus.
#
# D'où une asymétrie qui ressemble à tout SAUF à sa cause : disco OK dans les
# deux sens, `tailscale ping` du pair en timeout, SYN TCP jamais posé, et une
# ACL parfaitement correcte qu'on accuse à tort pendant une heure.
#
# ⇒ On force le relais home sur la région où sont les pairs. Mesuré le 03/08 :
#   home `nyc` → inatteignable ; home `par` (région du laptop) → tout passe,
#   ACL stricte inchangée, sans aucun keepalive.
#
# ⚠️ `force-prefer-derp` est « until restart » : il ne survit pas à un
# redémarrage de tailscaled, donc il est réappliqué ici à chaque passage.
REGION=${TS_DERP_REGION:-}
if [ -z "$REGION" ]; then
  # Auto : la région la plus fréquente chez les pairs EN LIGNE. C'est là que se
  # trouvent les gens qui veulent nous joindre.
  REGION=$($TS status --json 2>/dev/null | node -e "
    let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{try{
      const j=JSON.parse(s);
      const n={}; for(const p of Object.values(j.Peer||{}))
        if(p.Online && p.Relay) n[p.Relay]=(n[p.Relay]||0)+1;
      const top=Object.entries(n).sort((a,b)=>b[1]-a[1])[0];
      console.log(top?top[0]:'');
    }catch{console.log('')}});" 2>/dev/null)
  [ -n "$REGION" ] && log "région la plus peuplée chez les pairs en ligne : $REGION"
fi
if [ -n "$REGION" ]; then
  # `force-prefer-derp` veut un ID numérique ; les pairs donnent un CODE ("par").
  ID=$($TS debug derp-map 2>/dev/null | node -e "
    let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{try{
      const j=JSON.parse(s), code=process.argv[1];
      for(const [id,r] of Object.entries(j.Regions||{}))
        if(r.RegionCode===code) return console.log(id);
      console.log('');
    }catch{console.log('')}});" "$REGION" 2>/dev/null)
  if [ -n "$ID" ]; then
    timeout 20 $TS debug force-prefer-derp "$ID" >> "$DIR/tailscaled.log" 2>&1
    timeout 20 $TS debug break-derp-conns  >> "$DIR/tailscaled.log" 2>&1
    sleep 10
    log "relais home forcé sur $REGION (région $ID) — sinon l'entrant ne passe pas"
  else
    log "⚠️ région $REGION introuvable dans la DERP map, relais home laissé au défaut"
  fi
else
  log "⚠️ aucun pair en ligne : relais home laissé au défaut. Si l'entrant ne"
  log "   passe pas, relancer ce script une fois un pair connecté, ou forcer"
  log "   la région à la main : TS_DERP_REGION=par bash tunnel_up.sh"
fi

# ── 5. La console sur le tailnet. `serve`, jamais `funnel` : voir l'en-tête.
log "publication du port $PORT sur le tailnet (serve, pas funnel)"
timeout 40 $TS serve --bg "$PORT" >> "$DIR/tailscaled.log" 2>&1 \
  || die "serve a échoué — voir $DIR/tailscaled.log"

echo
$TS status | head -3
echo
# ⚠️ Le nom se lit dans `.Self`, pas dans le PREMIER `DNSName` du JSON. Un
# `grep -o … | head -1` rendait une chaîne vide : l'ordre des clés n'est pas
# garanti et `Self` n'est pas forcément en tête. Lire une structure avec un
# outil qui ne la comprend pas marche jusqu'au jour où elle change d'ordre.
NOM=$($TS status --json 2>/dev/null | node -e \
  "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{
     try { const j=JSON.parse(s);
       console.log(j.Self.DNSName.replace(/\\.$/,''),
                   j.Self.Tags ? '· '+j.Self.Tags.join(',') : '· 🔴 NON TAGUÉ'); }
     catch { console.log('(nom indéterminé)'); } })" 2>/dev/null)
log "console sur le tailnet · https://${NOM%% *}/  ${NOM#* }"
log "⚠️ tailnet SEUL — rien n'est exposé sur l'internet public."
# ⚠️ Ne PAS tenter de valider l'accès en curl depuis ici : la VM ne résout pas
# MagicDNS (`--accept-dns=false`) et son proxy de session rend 502 sur un nom
# non public. Un échec ici ne prouve rien sur l'ACL — seul un poste du tailnet
# peut le vérifier. Mesuré le 03/08, voir §3 ter du dossier.
