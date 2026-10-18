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
kv "boot"          "$(date -u -d "$(uptime -s)" '+%F %T') UTC"   # uptime -s parle en heure LOCALE (TZ) : converti explicitement
kv "uptime"        "$(awk '{printf "%d min", $1/60}' /proc/uptime)"
kv "disque libre"  "$(df -h / | awk 'NR==2{print $4" libres sur "$2" affichés — le quota est le chiffre LIBRE"}')"

sec "Horloge (18/10 : pas de démon NTP dans la VM — l'heure vient de l'hôte, juste à la seconde ; le fuseau est UTC sauf TZ)"
kv "fuseau"        "TZ=${TZ:-—} · /etc/localtime → $(readlink /etc/localtime 2>/dev/null | sed 's#.*/zoneinfo/##') · date dit $(date '+%T %Z')"
ntpd_vu=$(for d in chronyd ntpd systemd-timesyncd; do command -v "$d" 2>/dev/null; done | tr '\n' ' ')
kv "démon NTP"     "${ntpd_vu:-— (aucun)}"
kv "noyau"         "$(python3 - <<'PY'
import ctypes
class TX(ctypes.Structure):
    _fields_ = [('modes', ctypes.c_uint), ('offset', ctypes.c_long), ('freq', ctypes.c_long), ('maxerror', ctypes.c_long),
                ('esterror', ctypes.c_long), ('status', ctypes.c_int), ('constant', ctypes.c_long), ('precision', ctypes.c_long),
                ('tolerance', ctypes.c_long), ('tv_sec', ctypes.c_long), ('tv_usec', ctypes.c_long), ('tick', ctypes.c_long),
                ('ppsfreq', ctypes.c_long), ('jitter', ctypes.c_long), ('shift', ctypes.c_int), ('stabil', ctypes.c_long),
                ('jitcnt', ctypes.c_long), ('calcnt', ctypes.c_long), ('errcnt', ctypes.c_long), ('stbcnt', ctypes.c_long),
                ('tai', ctypes.c_int), ('pad', ctypes.c_int * 11)]
t = TX(); ctypes.CDLL(None).adjtimex(ctypes.byref(t))
print(('NON disciplinée (STA_UNSYNC)' if t.status & 0x40 else 'disciplinée') + ' · freq %+.3f ppm · tick %d' % (t.freq / 65536, t.tick))
PY
) · clocksource $(cat /sys/devices/system/clocksource/clocksource0/current_clocksource)"
# L'écart, contre l'en-tête Date de pypi.org (dans noProxy, donc joignable de toute session ; CDN à l'heure) :
# résolution 1 s, juste si |écart| < 0,5 s. api.github.com ne convient pas : à travers le proxy, HEAD donne 400.
t0=$(date +%s.%N); dh=$(curl -s -D - -o /dev/null --max-time 5 https://pypi.org/simple/ 2>/dev/null | tr -d '\r' | grep -i '^date:' | head -1 | cut -d' ' -f2-); t1=$(date +%s.%N)
if [ -n "$dh" ]; then
  kv "écart vs pypi.org" "$(python3 -c "from email.utils import parsedate_to_datetime as p; print('%+.2f s (résolution 1 s, aller-retour %.2f s)' % ((($t0 + $t1) / 2) - p('$dh').timestamp(), $t1 - $t0))")"
else
  kv "écart vs pypi.org" "pas d'en-tête Date (réseau ?)"
fi

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
  echo "posé le $(date -u '+%F %T') UTC, VM bootée à $(date -u -d "$(uptime -s)" '+%F %T') UTC" > "$CANARY"
  kv "posé" "$CANARY"
  echo "  (au prochain réveil : présent ⇒ le workdir a survécu · absent ⇒ VM neuve + clone frais)"
fi
