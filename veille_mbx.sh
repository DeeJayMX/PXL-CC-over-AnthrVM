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
# Toutes les 60 s, UN curl de l'annuaire (`/api/turbohq/mbx`, lecture seule) — jamais `mbx.js who`, qui lance un Node
# complet à chaque appel (la carte voyait « des sessions SSH courtes s'enchaîner », 15/10). Dès qu'un message attend :
# `mbx.js read` (la boîte se VIDE), on l'imprime et on SORT — la fin de la tâche réveille la session, qui traite puis
# RÉARME. Au terme de la fenêtre (6900 s, sous le plafond de 2 h d'une tâche de fond) : « fin de fenêtre », à réarmer.
# ⭐ Il écrit un TÉMOIN DE VIE à chaque tour (`/tmp/veille-mbx.vivant`, l'heure) : c'est ce que lit la tâche planifiée
# horaire pour savoir s'il tourne — `pgrep -f` se trouverait lui-même dans la ligne de commande qui le cherche.
# ⚠️ Ce n'est que la moitié : quand le conteneur est recyclé, la veille meurt avec lui. L'autre moitié est la tâche
# planifiée horaire de la session (« Veille MBX pxl-switcher »).
BOITE="${1:-pxl-switcher}"; FENETRE="${2:-6900}"
ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
U=http://127.0.0.1:8720
M=/home/radxa/turbohq/pxl-turbohq-client/bin/mbx.js
VIVANT=/tmp/veille-mbx.vivant
remonter() { TS_DIR="$ICI/.tailscale" timeout 120 bash "$ICI/tunnel_up.sh" 8710 >/dev/null 2>&1; }
carte() { timeout 40 ssh -o ConnectTimeout=20 -o BatchMode=yes pxl-tx "$1"; }

fin=$(( $(date +%s) + FENETRE )); echecs=0
while [ "$(date +%s)" -lt $fin ]; do
  date -u +%s > "$VIVANT"
  n=$(carte "curl -s -m 5 $U/api/turbohq/mbx" 2>/dev/null | python3 -c "
import sys, json
try: print(next((b.get('queued', 0) for b in json.load(sys.stdin) if b.get('name') == '$BOITE'), 0))
except Exception: pass")
  if [ -z "$n" ]; then
    echecs=$((echecs + 1))
    [ $echecs = 3 ] && remonter                                                   # tunnel tombé : on le relève
    [ $echecs = 10 ] && echo "$(date -u +%H:%M:%S) [veille] pxl-tx injoignable depuis ~10 min"
  else
    echecs=0
    if [ "$n" -gt 0 ]; then
      echo "$(date -u +%H:%M:%S) [veille] $n message(s) pour $BOITE :"
      carte "MBX_URL=$U timeout 15 node $M --as $BOITE read" 2>&1 | sed 's/\r$//'
      rm -f "$VIVANT"
      exit 0
    fi
  fi
  sleep 60
done
rm -f "$VIVANT"
echo "$(date -u +%H:%M:%S) [veille] fin de fenêtre, rien reçu"
