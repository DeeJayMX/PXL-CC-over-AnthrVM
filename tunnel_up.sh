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
# ⭐ Ce qui PEUT être persistant, c'est la **clé d'authentification**, et elle
# doit vivre là où la VM ne peut pas l'emporter dans sa tombe : dans les
# variables d'environnement de l'environnement Claude Code, qui sont
# reconfigurées à chaque démarrage de session. La VM redevient neuve, la clé la
# réattend. C'est le seul endroit du dispositif qui survive à un recyclage sans
# être un dépôt git.
#
#   Où la poser  : réglages de l'environnement Claude Code → variables
#                  d'environnement → `TS_AUTHKEY`
#   Quelle clé   : une auth key **réutilisable** (Tailscale admin → Settings →
#                  Keys → Generate auth key → Reusable). Une clé à usage unique
#                  ne servirait qu'une session, ce qui ne résout rien.
#   Durée de vie : 90 jours au maximum côté Tailscale. Ça ne se contourne pas —
#                  il faudra la régénérer, et ce script le dira clairement le
#                  jour où elle expirera plutôt que d'échouer en silence.
#
# ⚠️ La clé n'est jamais affichée, jamais écrite sur le disque, jamais passée en
# argument de ligne de commande — `ps` est lisible par tout le monde. Elle ne
# transite que par l'environnement du processus `tailscale up`.
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

    C'est le seul endroit où une clé survit à un recyclage de VM :
      réglages de l'environnement Claude Code → variables d'environnement
      TS_AUTHKEY = tskey-auth-…   (auth key RÉUTILISABLE, 90 j max)

    Ni le workdir ni ce dépôt ne conviennent — le premier disparaît, le second
    publierait un secret. Voir l'en-tête de ce fichier."
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

# ── 4. L'authentification. La clé passe par l'ENVIRONNEMENT du processus, pas
#      par la ligne de commande : `ps aux` est lisible par n'importe qui.
if $TS status > /dev/null 2>&1; then
  log "nœud déjà authentifié"
else
  log "authentification par clé (relais DERP — l'egress interdit le direct)"
  if ! TS_AUTHKEY="$TS_AUTHKEY" timeout 90 "$DIR/tailscale" --socket="$DIR/ts.sock" up \
       --auth-key="$TS_AUTHKEY" --hostname="${TS_HOSTNAME:-pxl-console}" \
       --accept-dns=false >> "$DIR/tailscaled.log" 2>&1; then
    die "authentification refusée.

    La cause la plus probable est une clé EXPIRÉE — Tailscale les plafonne à
    90 jours — ou à usage unique déjà consommée. En régénérer une réutilisable
    et la reposer dans TS_AUTHKEY. Détail : $DIR/tailscaled.log"
  fi
fi

# ── 5. La console sur le tailnet. `serve`, jamais `funnel` : voir l'en-tête.
log "publication du port $PORT sur le tailnet (serve, pas funnel)"
timeout 40 $TS serve --bg "$PORT" >> "$DIR/tailscaled.log" 2>&1 \
  || die "serve a échoué — voir $DIR/tailscaled.log"

echo
$TS status | head -3
echo
log "console accessible sur le tailnet · $($TS status --json 2>/dev/null \
  | grep -o '"DNSName":"[^"]*"' | head -1 | cut -d'"' -f4 | sed 's/\.$//')"
log "⚠️ tailnet SEUL — rien n'est exposé sur l'internet public."
