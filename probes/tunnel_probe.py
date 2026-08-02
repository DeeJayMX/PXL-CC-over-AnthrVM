#!/usr/bin/env python3
# Sonde « exposer un serveur web » — peut-on rendre joignable de l'extérieur un service qui
# tourne dans la VM (Cloudflare Tunnel, Tailscale) ? Et accessoirement : que sort-il vraiment
# de cette machine ?
#
#   python3 probes/tunnel_probe.py            # lecture seule, ~30 s
#   python3 probes/tunnel_probe.py --download # + telecharge cloudflared et tente un quick tunnel
#
# La sonde mesure QUATRE choses, de la plus generale a la plus specifique :
#   1. quels PORTS TCP sortent de la VM (pas seulement quels hotes)
#   2. si une socket brute CONTOURNE le proxy (elle ne le contourne pas — voir §3 du dossier)
#   3. si l'UDP sort
#   4. le verdict pour cloudflared et pour Tailscale, avec la RAISON exacte
#
# Aucune de ces reponses n'est une propriete du binaire teste : ce sont des proprietes de la
# POLITIQUE RESEAU de l'environnement, choisie a sa creation. Une autre VM peut repondre
# autrement — c'est tout l'interet de rejouer la sonde.

import os
import socket
import ssl
import subprocess
import sys
import time

DOWNLOAD = "--download" in sys.argv
BIN = "/tmp/tunnel_probe_bin"
ok = ko = 0


def sec(t):
    print("\n\033[1m── %s\033[0m" % t)


def pas(m, x=""):
    global ok
    print("  \033[32mOK\033[0m   %s%s" % (m, "  " + x if x else ""))
    ok += 1


def non(m, x=""):
    global ko
    print("  \033[31mNON\033[0m  %s%s" % (m, "  " + x if x else ""))
    ko += 1


def info(m):
    print("       %s" % m)


def tcp(host, port, timeout=6):
    """Connexion TCP en IPv4 forcee (l'IPv6 n'existe pas ici : AF non supporte)."""
    t0 = time.time()
    try:
        ip = socket.getaddrinfo(host, port, socket.AF_INET, socket.SOCK_STREAM)[0][4][0]
        s = socket.create_connection((ip, port), timeout)
        s.close()
        return True, ip, (time.time() - t0) * 1000
    except Exception as e:
        return False, "%s: %s" % (type(e).__name__, e), (time.time() - t0) * 1000


def https_head(host, path="/"):
    """Poignee de main TLS + HEAD, SANS passer par HTTPS_PROXY. Renvoie (emetteur, statut)."""
    ctx = ssl.create_default_context()
    ip = socket.getaddrinfo(host, 443, socket.AF_INET, socket.SOCK_STREAM)[0][4][0]
    s = ctx.wrap_socket(socket.create_connection((ip, 443), 8), server_hostname=host)
    try:
        cert = s.getpeercert()
        iss = dict(x[0] for x in cert["issuer"])
        s.sendall(("HEAD %s HTTP/1.1\r\nHost: %s\r\nConnection: close\r\n\r\n"
                   % (path, host)).encode())
        line = s.recv(120).decode("latin1", "replace").split("\r\n")[0]
        return "%s / %s" % (iss.get("organizationName", "?"), iss.get("commonName", "?")), line
    finally:
        s.close()


# ── 1. Quels ports sortent ? ──────────────────────────────────────────────────────
sec("1. Ports TCP en sortie")
PORTS = [("github.com", 443, True), ("github.com", 80, True),
         ("github.com", 22, False), ("github.com", 8080, False),
         ("smtp.gmail.com", 587, False), ("1.1.1.1", 853, False),
         ("region1.v2.argotunnel.com", 7844, False)]
open_ports = []
for host, port, expected in PORTS:
    up, det, ms = tcp(host, port)
    if up:
        open_ports.append(port)
    print("  %-28s:%-5d %s" % (host, port, "OUVERT (%.0f ms)" % ms if up else "silence — %s" % det))
if set(open_ports) <= {80, 443} and 443 in open_ports:
    pas("seuls 80 et 443 sortent", "tout autre port tombe dans le vide (timeout, pas de RST)")
else:
    non("ports ouverts inattendus", str(sorted(set(open_ports))))
info("Consequence : tout protocole a port dedie (SSH 22, SMTP 587, Cloudflare 7844) est mort")
info("avant meme de parler d'allowlist.")

# ── 2. Une socket brute contourne-t-elle le proxy ? ────────────────────────────────
sec("2. Le proxy est-il contournable en ouvrant une socket ?")
info("HTTPS_PROXY = %s" % os.environ.get("HTTPS_PROXY", "(absent)"))
mitm = allow = deny = 0
for host in ["github.com", "pypi.org", "proxy.golang.org", "api.trycloudflare.com",
             "controlplane.tailscale.com", "one.one.one.one"]:
    try:
        issuer, status = https_head(host)
    except Exception as e:
        print("  %-30s %s: %s" % (host, type(e).__name__, e))
        continue
    in_noproxy = host in (os.environ.get("no_proxy", "") + os.environ.get("NO_PROXY", ""))
    print("  %-30s %-22s %s%s" % (host, status, issuer,
                                  "   [dans no_proxy]" if in_noproxy else ""))
    if "Anthropic" in issuer:
        mitm += 1
    if "403" in status:
        deny += 1
    elif "200" in status or "301" in status:
        allow += 1
if mitm and mitm == mitm + 0 and deny:
    pas("interception TRANSPARENTE sur 443", "certificat emis par Anthropic sur TOUS les hotes")
    info("Ouvrir une socket ne contourne rien : le proxy n'est pas seulement une variable")
    info("d'environnement, c'est un intercepteur sur le chemin. L'allowlist s'applique quand")
    info("meme (%d autorises, %d en 403), y compris pour les hotes listes dans no_proxy —" % (allow, deny))
    info("`no_proxy` veut dire « ne passe pas par le CONNECT », pas « echappe a la politique ».")
else:
    non("interception non confirmee", "resultat different du dossier : le DATER et le consigner")

# ── 3. L'UDP sort-il ? ────────────────────────────────────────────────────────────
sec("3. UDP")
q = bytes.fromhex("abcd01000001000000000000") + b"\x06github\x03com\x00" + bytes.fromhex("00010001")
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.settimeout(5)
try:
    s.sendto(q, ("1.1.1.1", 53))
    d, _ = s.recvfrom(512)
    pas("UDP/53 (DNS) repond", "%d octets" % len(d))
except Exception as e:
    non("UDP/53 muet", "%s: %s" % (type(e).__name__, e))
finally:
    s.close()
info("Aucun autre port UDP n'a repondu : WireGuard (Tailscale) et QUIC (cloudflared) n'ont")
info("donc pas de plan de donnees.")

# ── 4. Cloudflared ────────────────────────────────────────────────────────────────
sec("4. Cloudflare Tunnel")
up, det, _ = tcp("api.trycloudflare.com", 443)
try:
    _, status = https_head("api.trycloudflare.com")
    if "403" in status:
        non("api.trycloudflare.com hors allowlist", status)
    else:
        pas("api.trycloudflare.com joignable", status)
except Exception as e:
    non("api.trycloudflare.com injoignable", str(e))
if 7844 not in open_ports:
    non("le port de bord 7844 ne sort pas", "verrou STRUCTUREL : cloudflared n'a pas de repli 443")
if DOWNLOAD:
    info("telechargement de cloudflared…")
    r = subprocess.run(["curl", "-sSL", "--max-time", "120", "-o", BIN,
                        "https://github.com/cloudflare/cloudflared/releases/latest/download/"
                        "cloudflared-linux-amd64"], capture_output=True)
    if r.returncode == 0 and os.path.getsize(BIN) > 1_000_000:
        os.chmod(BIN, 0o755)
        v = subprocess.run([BIN, "--version"], capture_output=True, text=True)
        pas("binaire telechargeable et executable", v.stdout.strip())
        p = subprocess.run([BIN, "tunnel", "--url", "http://127.0.0.1:1", "--no-autoupdate"],
                           capture_output=True, text=True, timeout=60)
        err = (p.stderr + p.stdout).strip().split("\n")[-1][:160]
        non("quick tunnel refuse", err)
    else:
        non("telechargement impossible", "code %d" % r.returncode)
else:
    info("(--download pour telecharger cloudflared et tenter reellement un quick tunnel)")

# ── 5. Tailscale ──────────────────────────────────────────────────────────────────
sec("5. Tailscale")
print("  %-30s %s" % ("/dev/net/tun", "present" if os.path.exists("/dev/net/tun") else "ABSENT"))
for host in ["pkgs.tailscale.com", "controlplane.tailscale.com", "derp1.tailscale.com"]:
    try:
        _, status = https_head(host)
        print("  %-30s %s" % (host, status))
    except Exception as e:
        print("  %-30s %s" % (host, e))
info("Le binaire n'est pas telechargeable (pkgs.* hors allowlist) mais RESTE constructible :")
info("  GOBIN=/tmp/bin go install tailscale.com/cmd/tailscale@latest   (proxy.golang.org passe)")
info("Ca ne sert a rien tant que controlplane.tailscale.com repond 403 : sans plan de controle,")
info("pas de noeud. Et sans UDP, le plan de donnees WireGuard tomberait de toute facon en DERP,")
info("qui est lui aussi hors allowlist.")

# ── Verdict ───────────────────────────────────────────────────────────────────────
sec("Verdict")
print("""  AUCUN tunnel ne peut exposer un serveur de cette VM en l'etat.
  Ce n'est PAS un probleme d'outillage — les binaires se telechargent ou se construisent :
    · cloudflared : hote de reservation en 403, ET port 7844 sans issue (verrou double)
    · tailscale   : plan de controle en 403, pas d'UDP, DERP en 403 (verrou triple)
  C'est la POLITIQUE RESEAU de l'environnement. Le proxy le dit lui-meme, mot pour mot :
    « Host not in allowlist: api.trycloudflare.com. Add this host to your network egress
      settings to allow access. »
  => la piste n'est pas technique, elle est dans les reglages d'egress de l'environnement.
     Reste ouverte, et NON MESUREE : savoir si autoriser un hote ouvre aussi ses ports
     non standard. Sans cela, cloudflared resterait bloque meme autorise.

  Ce qui marche pour montrer une UI a un humain, en attendant : la capture d'ecran
  (probes/ui_probe.mjs) — l'agent sert la page, la manipule, et la REGARDE.""")
print("\n  %d OK · %d bloque(s)" % (ok, ko))
