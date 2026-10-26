#!/usr/bin/env bash
# cache.sh 1h | 5m | (rien) — durée du cache de prompt de la session (`promptCacheTtl`).
#
# Pourquoi deux réglages (26/10/2026, Eliott : « le cache d'1 h n'est valable que quand on bosse en
# mode sérieux, faut que ça soit modifiable ») : une écriture de cache est facturée plus cher en 1 h
# qu'en 5 min (doc des réglages, `promptCacheTtl`). Le 1 h ne rapporte que si on revient APRÈS plus de
# 5 min et AVANT l'heure — une séance de travail suivie. Pour une question ponctuelle ou de longues
# absences, 5 min coûte moins.
#   1h = défaut versionné · 5m = question ponctuelle suivie de longues absences.
# ⚠️ Mesuré le même soir dans le journal de session : avec 300-800 k jetons de contexte, UNE pause de 5 à
# 60 min en 5m réécrit tout (~$1,5-4) ; le 1h ne coûte plus cher qu'au retour après plus d'une heure.
#
# Ce qu'il écrit : /home/user/.claude/settings.json, le fichier que lit une session ouverte sur
# /home/user (plusieurs dépôts — ce sont aussi ses hooks qui y vivent). ⚠️ Une session à PLUSIEURS
# dépôts ne lit, dans le .claude/settings.json de chaque dépôt, que les plugins (doc « Settings in
# cloud sessions ») : la valeur versionnée de PXL-Switcher ne vaut que pour une session ouverte sur
# lui seul.
# 🔴 Précédence : FORCE_PROMPT_CACHING_5M > CLAUDE_CODE_PROMPT_CACHE_TTL > ce réglage. Une variable
# d'environnement posée dans l'environnement cloud BLOQUE donc la bascule : ne pas la poser.
# La doc dit que les fichiers de réglages sont relus à chaud ; la durée réellement en vigueur se lit
# avec /usage (côté Eliott — je n'ai aucun instrument pour la voir).
set -eu
F=/home/user/.claude/settings.json
case "${1:-}" in
  1h|5m)
    [ -f "$F" ] || { echo "🔴 $F absent — poser d'abord settings-parent.json (voir CLAUDE.md)"; exit 1; }
    node -e '
      const fs = require("fs"), [f, v] = process.argv.slice(1);
      const s = JSON.parse(fs.readFileSync(f, "utf8"));
      const o = { promptCacheTtl: v };
      for (const [k, x] of Object.entries(s)) if (k !== "promptCacheTtl") o[k] = x;
      fs.writeFileSync(f + ".tmp", JSON.stringify(o, null, 2) + "\n");
      fs.renameSync(f + ".tmp", f);' "$F" "$1" ;;
  "") ;;
  *) echo "usage : bash cache.sh 1h|5m   (sans argument : dit ce qui est posé)"; exit 2 ;;
esac
printf 'promptCacheTtl : %s  (%s)\n' \
  "$(node -e 'try{console.log(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).promptCacheTtl??"non posé")}catch{console.log("illisible")}' "$F")" "$F"
for v in FORCE_PROMPT_CACHING_5M CLAUDE_CODE_PROMPT_CACHE_TTL ENABLE_PROMPT_CACHING_1H; do
  [ -n "${!v:-}" ] && echo "⚠️  $v=${!v} est posée dans l'environnement : elle passe devant ce réglage"
done
exit 0
