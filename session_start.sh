#!/usr/bin/env bash
# Démarrage automatique de la console PXL + du tunnel Tailscale, à chaque
# invocation de session. Appelé par le hook SessionStart de .claude/settings.json.
#
#   bash session_start.sh          # aussi lançable à la main, sans risque
#
# ─── Pourquoi ce fichier existe ───────────────────────────────────────────────
#
# Le nœud Tailscale est ÉPHÉMÈRE et la VM est recyclée : à chaque réveil il faut
# relancer la console puis le tunnel, dans cet ordre (publier `serve` sur un port
# mort ne sert à rien). Le faire à la main veut dire le redemander à chaque fois ;
# ce script le fait tout seul.
#
# ⚠️ Il y a une SECONDE raison, moins évidente : le port du proxy de sortie de la
# session change quand l'infrastructure redémarre (mesuré le 03/08 : 43003 →
# 41577). `tailscaled` mémorise ce port à son démarrage — quand il bouge, le
# démon perd sa sortie et MEURT. Ce script détecte ce cas précis et le répare,
# ce qu'aucune relance naïve ne ferait.
#
# ─── Trois règles de conduite d'un hook ───────────────────────────────────────
#
#  1. **Il sort toujours en 0.** Un hook qui échoue fait échouer le démarrage de
#     la session. Rien ici ne vaut de perdre une session.
#  2. **Il est idempotent.** Sur une session déjà chaude il ne relance rien et
#     rend la main en deux secondes ; c'est ce qui permet de le brancher sur
#     `startup|resume` sans coût.
#  3. **Il est borné.** Un `timeout` global l'empêche de suspendre un démarrage
#     de session si le réseau part en vrille.
#
# Détail complet et mesures : DOSSIER_VM.md §3 ter.
set -uo pipefail

ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONSOLE=${PXL_CONSOLE_DIR:-/home/user/PXL-Switcher/console}
PORT=${PXL_CONSOLE_PORT:-8710}
LOG=${PXL_SESSION_LOG:-/tmp/pxl-session-start.log}

dire() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*" | tee -a "$LOG"; }

# ⚠️ Uniquement dans une session cloud. En local, cette machine n'est pas la VM
# et il n'y a ni tunnel ni console à y monter. `CLAUDE_CODE_REMOTE` vaut `true`
# dans la VM et n'est JAMAIS vrai ailleurs — c'est le test recommandé par la doc.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

: > "$LOG"
dire "démarrage de session — console:$PORT + tunnel"

# ── 1. La console. Sans elle, publier `serve` exposerait un port mort.
if pgrep -f "server.mjs --port $PORT" > /dev/null 2>&1; then
  dire "console déjà en service"
else
  if [ -z "${PXL_CONSOLE_MOTDEPASSE:-}" ]; then
    # On démarre quand même : le serveur tire un mot de passe et l'écrit dans son
    # propre journal, en 0600. Mais il changera à chaque réveil, ce qui rend la
    # console inutilisable en pratique — d'où l'avertissement plutôt qu'un
    # silence.
    dire "⚠️ PXL_CONSOLE_MOTDEPASSE absent : un mot de passe est TIRÉ AU SORT et"
    dire "   changera à chaque réveil. Le poser dans les variables"
    dire "   d'environnement (claude.ai/code → icône nuage → roue dentée)."
  fi
  mkdir -p "${PXL_CONSOLE_ETAT:-$ICI/.etat-console}"
  ( cd "${PXL_CONSOLE_ETAT:-$ICI/.etat-console}" \
    && PXL_CONSOLE_ETAT="${PXL_CONSOLE_ETAT:-$ICI/.etat-console}" \
       node "$CONSOLE/server.mjs" --port "$PORT" --host 127.0.0.1 >> "$LOG" 2>&1 & )
  for _ in $(seq 1 15); do
    curl -s -o /dev/null --max-time 2 "http://127.0.0.1:$PORT/login.html" && break
    sleep 1
  done
  if curl -s -o /dev/null --max-time 3 "http://127.0.0.1:$PORT/login.html"; then
    dire "console démarrée sur 127.0.0.1:$PORT"
  else
    dire "⚠️ la console n'a pas répondu — voir $LOG"
  fi
fi

# ── 2. 🔴 Le piège du proxy qui a changé de port.
#
# `tailscaled` mémorise `$HTTPS_PROXY` à son démarrage. Quand l'infrastructure de
# la session redémarre, le port bouge et le démon meurt sur
# `connect: connection refused` vers l'ANCIEN port. Un démon vivant mais qui
# n'atteint plus le proxy est le pire cas : il a l'air sain et ne relaie rien.
# On le tue explicitement plutôt que d'espérer qu'il se répare.
PROXY_PORT=$(printf '%s' "${HTTPS_PROXY:-}" | sed -n 's#.*:\([0-9]\+\)/*$#\1#p')
if [ -n "$PROXY_PORT" ] && pgrep -f "tailscaled --tun=userspace-networking" > /dev/null 2>&1; then
  if grep -aq "connect: connection refused" "$ICI/.tailscale/tailscaled.log" 2>/dev/null \
     && ! grep -aq ":$PROXY_PORT" "$ICI/.tailscale/tailscaled.log" 2>/dev/null; then
    dire "⚠️ tailscaled tourne avec un proxy périmé (actuel : $PROXY_PORT) — on le relance"
    ps -eo pid,args | awk '/[t]ailscaled --tun=userspace-networking/ {print $1}' \
      | while read -r p; do kill "$p" 2>/dev/null; done
    sleep 3
    rm -f "$ICI/.tailscale/ts.sock"
  fi
fi

# ── 3. Le tunnel. `tunnel_up.sh` est lui-même idempotent : il ne relance pas ce
#      qui tourne, et il réapplique le relais home (« until restart ») à chaque
#      passage. Borné, pour ne jamais suspendre un démarrage de session.
if [ -z "${TS_AUTHKEY:-}" ]; then
  dire "⚠️ TS_AUTHKEY absent : pas de tunnel. Voir tunnel_up.sh pour où le poser."
else
  if timeout 120 bash "$ICI/tunnel_up.sh" "$PORT" >> "$LOG" 2>&1; then
    # ⚠️ `sed 's/.*· //'` prenait ce qui suit le DERNIER séparateur, donc le tag
    # au lieu de l'URL. On extrait l'URL elle-même, pas une position dans la ligne.
    URL=$(grep -ao 'https://[a-z0-9.-]*\.ts\.net/' "$LOG" | tail -1)
    dire "tunnel en place — $URL"
  else
    dire "⚠️ tunnel_up.sh a échoué ou dépassé 120 s — voir $LOG"
  fi
fi

dire "prêt."
exit 0
