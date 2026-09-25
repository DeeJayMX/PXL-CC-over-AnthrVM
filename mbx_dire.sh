#!/usr/bin/env bash
# Poster un message sur MBX — et NE PAS se tromper de forme.
#
#     bash mbx_dire.sh "mon texte"            # → boîte `all`, de la part de switch-dev
#     bash mbx_dire.sh "texte" tour           # → à la tour
#     echo "…" | bash mbx_dire.sh - all       # depuis stdin (les longs messages)
#
# 🔴🔴 **POURQUOI CE FICHIER EXISTE** (22/08). J'ai posté un compte rendu entier
# en envoyant `{"from":…,"to":…,"text":…}` dans le CORPS, par analogie avec les
# API qu'on écrit d'habitude. Le relais a répondu `{"delivered":4}` — donc **ça
# a réussi** — et le message est arrivé chez tout le monde signé **« anonyme »**,
# avec le JSON brut affiché comme texte.
#
# La forme réelle, lue dans `server_ws_transport.mjs` :
#   · le **CORPS EST LE TEXTE**, tel quel, aucun enrobage ;
#   · l'expéditeur est dans la **QUERY** : `?from=<nom>` (32 car.), défaut
#     `anonyme` ;
#   · la boîte est dans le **CHEMIN** : `/api/turbohq/mbx/<boîte>`.
#
# ⭐ *Un `{"delivered":4}` dit que le relais a rangé quelque chose, pas qu'il a
# rangé ce que je croyais.* Un code de retour n'est pas un contenu — motif 2 du
# `MISTAKE.md` du dépôt d'à côté, en version émission : je n'ai jamais RELU ce
# que j'avais envoyé.
#
# ⚠️ Et la leçon vaut au-delà de MBX : quand une API accepte un corps libre,
# **elle ne peut pas refuser** une forme inventée — donc rien ne sonnera jamais.
# C'est exactement le cas où il faut lire le récepteur avant d'écrire l'émetteur.

set -u

PORT=${MBX_PONT_PORT:-8099}
TEXTE=${1:-}
BOITE=${2:-all}
MOI=${MBX_AS:-switch-dev}

[ -n "$TEXTE" ] || { echo "usage: mbx_dire.sh <texte|-> [boîte]" >&2; exit 2; }
[ "$TEXTE" = "-" ] && TEXTE=$(cat)

# ⚠️ `--data-binary @-` : pas `-d`, qui replie les sauts de ligne. Le texte part
# tel qu'il est écrit — un compte rendu à puces doit arriver à puces.
REP=$(printf '%s' "$TEXTE" | curl -s --noproxy '*' --max-time 15 \
        -X POST "http://127.0.0.1:$PORT/api/turbohq/mbx/$BOITE?from=$MOI" \
        -H 'content-type: text/plain; charset=utf-8' --data-binary @-)

echo "envoyé en tant que « $MOI » vers « $BOITE » : $REP"

# ⭐ **ON RELIT CE QU'ON VIENT D'ÉCRIRE.** C'est le contrôle qui manquait : la
# signature et le texte tels que les autres les verront, pas tels qu'on les a
# voulus. Deux lignes, et elles auraient évité le « anonyme ».
curl -s --noproxy '*' --max-time 15 "http://127.0.0.1:$PORT/api/turbohq/mbx/$BOITE" \
  | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
      try { const a=JSON.parse(s); const m=a[a.length-1];
        if (!m) { console.log("⚠️ relecture : boîte vide"); return; }
        console.log(`relu → [${m.from} → ${m.to}] ${String(m.text).slice(0,120)}`);
      } catch { console.log("⚠️ relecture impossible (forme inattendue)"); } });' 2>/dev/null
