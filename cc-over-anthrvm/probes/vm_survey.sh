#!/usr/bin/env bash
# Relevé d'état d'une VM Claude Code. Lecture seule, ~10 s, aucun effet de bord
# sauf le canari (§4) qui écrit un fichier dans le workdir.
#
# À lancer EN DÉBUT DE SESSION : c'est ce qui dit sur quelle machine on se
# réveille, et si le workdir a survécu au dernier recyclage.
#
#   bash probes/vm_survey.sh              # relevé
#   bash probes/vm_survey.sh --canary     # + pose/relit le canari
#
# Toute divergence avec DOSSIER_VM.md est un fait nouveau : la mesurer, la dater,
# et l'y consigner. Ne jamais mettre à jour le dossier de mémoire.

set -uo pipefail
# dans le WORKDIR, pas dans $HOME (= /root) : c'est la survie du workdir qu'on teste
CANARY=${CANARY:-/home/user/.vm_canary}
sec(){ printf '\n\033[1m── %s\033[0m\n' "$1"; }
kv(){ printf '  %-30s %s\n' "$1" "$2"; }

sec "Machine"
kv "kernel"        "$(uname -sr)"
kv "firecracker"   "$(grep -qo firecracker-init /proc/cmdline && echo 'oui (firecracker-init)' || echo 'non vu dans /proc/cmdline')"
kv "cœurs"         "$(nproc)"
kv "RAM"           "$(free -g | awk '/Mem:/{print $2}') Go"
kv "CPU"           "$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ *//')"
kv "AVX-512"       "$(grep -m1 flags /proc/cpuinfo | tr ' ' '\n' | grep -c '^avx512') jeux"
kv "boot"          "$(uptime -s) UTC"
kv "uptime"        "$(awk '{printf "%d min", $1/60}' /proc/uptime)"
kv "disque libre"  "$(df -h / | awk 'NR==2{print $4" libres sur "$2" affichés — le quota est le chiffre LIBRE"}')"

sec "Persistance du workdir (le fait qui décide si un commit non poussé survit)"
BOOT=$(date -u -d "$(uptime -s)" +%s)
# $HOME vaut /root ici : les clones sont dans le répertoire de travail, pas chez l'utilisateur
WORK=${WORK:-/home/user}
for d in "$WORK"/*/; do
  [ -d "$d/.git" ] || continue
  n=$(git -C "$d" reflog --date=unix --format='%ad' 2>/dev/null | awk -v b="$BOOT" '$1 < b' | wc -l)
  kv "$(basename "$d")" "$([ "$n" -gt 0 ] && echo "clone SURVIVANT ($n entrées de reflog antérieures au boot)" || echo 'clone NEUF (reflog postérieur au boot)')"
done

sec "Réseau"
kv "HTTPS_PROXY" "${HTTPS_PROXY:-—}"
if [ -n "${HTTPS_PROXY:-}" ]; then
  st=$(curl -sS --max-time 10 "$HTTPS_PROXY/__agentproxy/status" 2>/dev/null || true)
  if [ -n "$st" ]; then
    printf '%s' "$st" | python3 -c 'import json,sys
d = json.load(sys.stdin)
for k in ("enabled", "selective", "toolScoped", "standalone"):
    print("  %-30s %s" % (k, d.get(k)))
print("  %-30s %d" % ("echecs de relais recents", len(d.get("recentRelayFailures", []))))' 2>/dev/null || kv "status" "illisible"
  else
    kv "status" "endpoint __agentproxy/status muet"
  fi
fi
# NB : curl sort 56 sur un CONNECT refuse et pipefail propage cet echec meme si grep
# a trouve — d'ou la capture prealable plutot qu'un pipe direct.
out=$(curl -sS -o /dev/null --max-time 10 https://mpv.io/ 2>&1 || true)
kv "hors allowlist (mpv.io)"  "$(printf '%s' "$out" | grep -o 'response 403' || echo 'joignable — allowlist élargie ?')"
kv "direct (pypi, noProxy)"   "HTTP $(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 https://pypi.org/simple/ 2>/dev/null)"
kv "metadata cloud"           "HTTP $(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 http://169.254.169.254/latest/meta-data/ 2>/dev/null)"
kv "API GitHub non scopée"    "$(curl -sS --max-time 10 https://api.github.com/zen 2>/dev/null | grep -o 'sessions are bound to their configured repositories' || echo 'pas de réécriture détectée')"

sec "Outillage"
for t in gh git node python3 clang gcc aarch64-linux-gnu-gcc qemu-aarch64 ffmpeg docker rustc go make cmake; do
  kv "$t" "$(command -v "$t" || echo '—')"
done
kv "chromium" "$( [ -e /opt/pw-browsers/chromium ] && "$(readlink -f /opt/pw-browsers/chromium)" --version 2>/dev/null || echo '—')"
kv "PLAYWRIGHT_BROWSERS_PATH" "${PLAYWRIGHT_BROWSERS_PATH:-—}"

if [ "${1:-}" = "--canary" ]; then
  sec "Canari"
  [ -f "$CANARY" ] && kv "précédent" "$(cat "$CANARY")" || kv "précédent" "aucun (première pose)"
  echo "posé le $(date -u '+%F %T') UTC, VM bootée à $(uptime -s)" > "$CANARY"
  kv "posé" "$CANARY"
  echo "  (au prochain réveil : présent ⇒ le workdir a survécu · absent ⇒ VM neuve + clone frais)"
fi
