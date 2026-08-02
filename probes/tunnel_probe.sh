#!/usr/bin/env bash
# Sonde « un tunnel sortant passe-t-il ? » — Tailscale, Cloudflare Tunnel, et
# plus généralement : quels ports l'egress de cette VM laisse-t-il sortir.
#
#   bash probes/tunnel_probe.sh            # ~30 s, lecture seule, aucun binaire téléchargé
#   bash probes/tunnel_probe.sh --full     # + télécharge tailscale/cloudflared et les lance
#
# Le verdict tient dans le tableau de ports : c'est lui qui décide, pas le client.
# Un client qui sait se replier en TCP/443 passe (Tailscale via DERP) ; un client
# dont le plan de données est cloué sur un autre port ne passe pas (cloudflared, 7844).
#
# ⚠️ La politique réseau est un réglage d'ENVIRONNEMENT, pas une propriété de la VM :
# elle change d'un environnement à l'autre. Toute divergence avec DOSSIER_VM.md §3bis
# est un fait nouveau : la mesurer, la dater, l'ajouter. Ne jamais mettre à jour.

set -uo pipefail
SP=${SP:-${TMPDIR:-/tmp}/tunnel_probe}
sec(){ printf '\n\033[1m── %s\033[0m\n' "$1"; }
kv(){ printf '  %-34s %s\n' "$1" "$2"; }

sec "Prérequis locaux (root + TUN : nécessaires, pas suffisants)"
kv "uid"            "$(id -u) ($(id -un))"
kv "/dev/net/tun"   "$([ -c /dev/net/tun ] && echo 'présent' || echo 'ABSENT')"
kv "CapEff"         "$(awk '/^CapEff/{print $2}' /proc/self/status)"
for b in tailscale tailscaled cloudflared wg ssh; do
  kv "$b préinstallé" "$(command -v $b || echo '—')"
done

sec "Ports en sortie DIRECTE (hors proxy) — c'est le tableau qui décide"
# Cibles connues ouvertes sur chaque port, pour qu'un timeout accuse le filtre et non l'hôte.
python3 - <<'EOF'
import socket
cibles = [
    ("93.184.215.14",    80, "TCP/80   HTTP"),
    ("140.82.112.3",    443, "TCP/443  HTTPS (github)"),
    ("159.89.225.99",   443, "TCP/443  DERP tailscale"),
    ("140.82.112.3",     22, "TCP/22   SSH"),
    ("8.8.8.8",         853, "TCP/853  DNS-over-TLS"),
    ("198.41.192.227", 7844, "TCP/7844 edge Cloudflare Tunnel"),
    ("159.89.225.99",  41641, "TCP/41641 WireGuard tailscale"),
]
for ip, p, lbl in cibles:
    s = socket.socket(); s.settimeout(6)
    try:
        s.connect((ip, p)); v = "OUVERT"
    except Exception as e:
        v = type(e).__name__
    finally:
        s.close()
    print("  %-34s %s" % (lbl, v))
EOF

sec "UDP en sortie (WireGuard direct et QUIC en dépendent)"
python3 - <<'EOF'
import socket, struct, os, time
def essai(host, port, pkt, lbl):
    try:
        ip = socket.getaddrinfo(host, port, socket.AF_INET, socket.SOCK_DGRAM)[0][4]
    except Exception as e:
        print("  %-34s DNS KO (%s)" % (lbl, type(e).__name__)); return
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.settimeout(6)
    t0 = time.time()
    try:
        s.sendto(pkt, ip); d, _ = s.recvfrom(2048)
        print("  %-34s REPONSE %d o en %d ms" % (lbl, len(d), (time.time()-t0)*1000))
    except Exception:
        print("  %-34s PAS DE REPONSE (filtré)" % lbl)
    finally:
        s.close()

dns = b'\xab\xcd\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00\x06google\x03com\x00\x00\x01\x00\x01'
stun = struct.pack(">HHI", 0x0001, 0, 0x2112A442) + os.urandom(12)
essai("8.8.8.8", 53, dns, "UDP/53   DNS (témoin)")
essai("derp1.tailscale.com", 3478, stun, "UDP/3478 STUN derp1")
essai("stun.l.google.com", 19302, stun, "UDP/19302 STUN google")
EOF

sec "Le proxy de session est-il soumis au même filtre ?"
if [ -n "${HTTPS_PROXY:-}" ]; then
  # ⚠️ Un « 200 Connection Established » ne prouve RIEN : le proxy l'émet AVANT
  # d'avoir joint la cible (errata 6). Seul le temps d'établissement TLS tranche.
  for u in "https://api.trycloudflare.com/" "https://region1.v2.argotunnel.com:7844/"; do
    r=$(timeout 45 curl -sS -x "$HTTPS_PROXY" -o /dev/null \
        -w 'code=%{http_code} tls=%{time_appconnect}s' "$u" 2>/dev/null)
    case "$r" in
      *"tls=0.000000s"*|"") kv "${u##*//}" "CONNECT accepté puis PENDU (tls jamais établi)" ;;
      *)                    kv "${u##*//}" "$r — relais réel" ;;
    esac
  done
  kv "recentRelayFailures" "$(curl -sS --max-time 10 "$HTTPS_PROXY/__agentproxy/status" 2>/dev/null \
      | python3 -c 'import json,sys;print(len(json.load(sys.stdin).get("recentRelayFailures",[])))' 2>/dev/null || echo '?')"
else
  kv "HTTPS_PROXY" "non défini"
fi

[ "${1:-}" = "--full" ] || { printf '\n  (--full pour lancer réellement tailscaled et cloudflared)\n'; exit 0; }

mkdir -p "$SP" && cd "$SP" || exit 1

sec "Tailscale — le plan de contrôle répond-il, et par quel chemin ?"
if [ ! -x ./tailscaled ]; then
  V=$(curl -sS "https://pkgs.tailscale.com/stable/?mode=json" \
      | python3 -c 'import sys,json;print(json.load(sys.stdin)["TarballsVersion"])' 2>/dev/null)
  kv "version" "${V:-indisponible}"
  curl -sSL -o ts.tgz "https://pkgs.tailscale.com/stable/tailscale_${V}_amd64.tgz" \
    && tar xzf ts.tgz && mv "tailscale_${V}_amd64"/tailscale* .
fi
rm -f ts.state ts.sock tsd.log
# --tun=userspace-networking : pas de route système touchée, la sonde reste sans effet de bord
(./tailscaled --tun=userspace-networking --state=./ts.state --socket=./ts.sock >tsd.log 2>&1 &)
sleep 10
timeout 120 ./tailscale --socket=./ts.sock netcheck 2>&1 | sed -n '/Report:/,/^$/p' | head -12
# L'URL de login prouve l'enregistrement d'un nœud : le plan de contrôle est joint.
timeout 60 ./tailscale --socket=./ts.sock up --hostname=vm-probe --accept-dns=false >/dev/null 2>&1
kv "AuthURL obtenue" "$(grep -o 'AuthURL is https://[^ ]*' tsd.log | head -1 | grep -q . && echo 'OUI — plan de contrôle joint, nœud enregistré' || echo 'non')"
kv "chemin emprunté" "$(grep -q 'tshttpproxy: CONNECT response' tsd.log && echo 'HTTPS_PROXY (tailscaled honore la variable)' || echo 'direct')"
timeout 30 ./tailscale --socket=./ts.sock logout >/dev/null 2>&1
pkill -f "tailscaled --tun=userspace-networking" 2>/dev/null
rm -f ts.state ts.sock   # ne laisser aucun nœud en attente d'autorisation

sec "Cloudflare Tunnel — plan de contrôle vs plan de données"
[ -x ./cloudflared ] || { curl -sSL -o cloudflared \
  "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64" \
  && chmod +x cloudflared; }
mkdir -p www && echo '<h1>probe</h1>' > www/index.html
(cd www && python3 -m http.server 8099 >/dev/null 2>&1 &)
sleep 2
timeout 70 ./cloudflared tunnel --url http://127.0.0.1:8099 --no-autoupdate --protocol http2 >cf.log 2>&1
pkill -f "http.server 8099" 2>/dev/null
kv "plan de contrôle (api, 443)" "$(grep -oE 'https://[a-z-]+\.trycloudflare\.com' cf.log | head -1 \
    | grep -q . && echo "hostname attribué : $(grep -oE 'https://[a-z-]+\.trycloudflare\.com' cf.log | head -1)" || echo 'ECHEC')"
kv "plan de données (edge, 7844)" "$(grep -q 'Unable to establish connection with Cloudflare edge' cf.log \
    && echo 'ECHEC — i/o timeout sur :7844' || echo 'établi')"

printf '\n  Verdict : un tunnel passe si et seulement si son plan de DONNEES sait\n'
printf '  se replier sur un port ouvert ci-dessus. Le plan de contrôle, lui, passe\n'
printf '  toujours — il parle 443. Ne pas confondre les deux.\n'
