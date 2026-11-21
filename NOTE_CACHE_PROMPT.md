# Cache de prompt de Claude Code — durée (5 min ou 1 h), ce qui la fait changer, comment la fixer

> Note datée du **20/11/2026**, écrite depuis un **poste local** (Windows, Claude Code 2.1.329, abonnement
> Claude, modèle Fable 5.2), pendant une session longue du projet L18. Même règle que le dossier : un fait
> nouveau **s'ajoute, daté** ; on n'écrase rien.
>
> Légende : **mesuré** (lu dans `/usage` de la session) · **documenté** (lu dans la doc officielle le 20/11/2026
> par un agent de recherche, non relu à la main) · **non vérifié**.

## ⭐ Le fait porteur

**Le cache de prompt passe tout seul de 1 h à 5 min dès qu'on sort du forfait** (plafond de dépense mensuel
atteint, puis usage supplémentaire acheté). Rien ne l'annonce. Sur une conversation longue, chaque pause de
plus de 5 minutes fait alors **réécrire toute la conversation** au tarif d'écriture.

Le réglage qui l'empêche existe, et il n'est pas posé par défaut :

```json
// ~/.claude/settings.json  (Windows : C:\Users\<nom>\.claude\settings.json)
{ "promptCacheTtl": "1h" }
```

Posé sur ce poste le 20/11/2026 (copie de l'ancien fichier à côté : `settings.json.avant-cache-1h`).

## Ce qui a été mesuré (20/11/2026, `/usage`)

| | |
|---|---|
| Coût estimé de la session | 116,02 $ |
| Durée d'API / durée d'horloge | 1 h 37 / 22 h 25 |
| Fable 5.2 | 738 jetons d'entrée, 561 400 de sortie, **78,2 M lus en cache**, **7,8 M écrits en cache** |
| Cache de la conversation principale | 150 requêtes, 88 % de l'entrée lue en cache, **15 échecs**, 5,9 M de jetons réécrits |
| Dernière ligne | `warm (5m TTL …)` ; cause probable affichée : « cache scope or TTL changed, usage-limit state changed, earlier messages changed » |

Calculé : 5,9 M / 15 ≈ **400 000 jetons réécrits par échec**, soit la taille de la conversation à ce moment.

Le même jour, plus tôt, la session annonçait un cache d'1 h. Entre les deux : plafond mensuel atteint
(message « You've hit your monthly spend limit », un sous-agent tué en vol), puis recharge.

## Ce que dit la documentation (20/11/2026)

Page : <https://code.claude.com/docs/en/prompt-caching.md>, sections « Which TTL each request gets » et
« Choose the TTL yourself ». Demande Claude Code **2.1.242 ou plus récent**.

**Par défaut**

- Abonnement Claude, dans le forfait inclus : **1 h** pour la conversation principale.
- Usage supplémentaire (crédits), clé API, fournisseur cloud : **5 min**.

**Réglages, par ordre de priorité**

| Réglage | Portée | Valeurs |
|---|---|---|
| `FORCE_PROMPT_CACHING_5M=1` | tout, priorité maximale | — |
| `CLAUDE_CODE_PROMPT_CACHE_TTL` | conversation principale (variable d'environnement) | `5m`, `1h` |
| `promptCacheTtl` | conversation principale (`settings.json`) | `5m`, `1h` |
| `CLAUDE_CODE_SUBAGENT_PROMPT_CACHE_TTL` / `subagentPromptCacheTtl` | sous-agents | `5m`, `1h` |
| `cacheTtl` dans l'en-tête d'un sous-agent | ce sous-agent (ignoré en usage crédits) | — |
| `ENABLE_PROMPT_CACHING_1H=1` | les deux | — |
| `DISABLE_PROMPT_CACHING` | coupe le cache | — |

Toute autre valeur que `5m` ou `1h` est ignorée.

**Prix** (<https://platform.claude.com/docs/en/build-with-claude/prompt-caching>, section Pricing), en
multiple du prix normal de l'entrée :

| | |
|---|---|
| Écriture en cache 5 min | × 1,25 |
| Écriture en cache 1 h | × 2 |
| Lecture en cache | × 0,1 (× 0,05 sur Opus 5.5 et Sonnet 5.5 ; **× 0,025 sur Fable 5.x et Mythos 5.x**) |

## Ce qu'il faut en retenir

- **1 h est le bon choix dès qu'on fait des pauses** : écrire une fois à × 2 coûte moins que réécrire deux
  fois à × 1,25. Avec un travail par sous-agents (20 à 45 minutes sans message), le cache de 5 minutes
  expire à chaque retour d'agent.
- **Sous-agents laissés à 5 min** : ils enchaînent leurs appels sans pause, le cache court leur suffit et
  coûte moins à écrire.
- **Le vrai levier reste la taille de la conversation** : un cache expiré coûte ce que pèse la
  conversation. `/clear` après chaque lot, avec une note de reprise tenue à jour dans le dépôt.
- **Diagnostic** : `/usage` (ligne « Prompt cache (main) », durée affichée à la fin) ;
  `claude -p "hello" --output-format json` montre `ephemeral_1h_input_tokens` et
  `ephemeral_5m_input_tokens` dans `usage.cache_creation`.

## ⚠️ Non vérifié

- Que `promptCacheTtl: "1h"` soit **accepté en usage supplémentaire** sur un abonnement : la doc dit de le
  poser pour garder 1 h, sans écrire qu'il est honoré dans ce cas. À contrôler dans `/usage` (« 1h TTL »).
- Que le réglage s'applique à la **session en cours**, ou seulement à la suivante.
- Le prix réel des écritures en usage supplémentaire, et l'équivalence de ces multiplicateurs pour un
  abonnement : non documentés.
- Qu'un changement de durée **invalide** le cache existant : `/usage` le donne comme cause probable, la
  doc ne le liste pas parmi les actions qui invalident.
- Rien de tout cela n'a été mesuré dans une **session cloud** (la VM de ce dossier) : seulement en local.

## ⭐ Ajout du 20/11/2026, quelques minutes après : deux des points « non vérifiés » sont tranchés

**Mesuré**, second `/usage` de la même session, après avoir posé `promptCacheTtl: "1h"` :

| | |
|---|---|
| Dernière ligne | `warm (1h TTL, last activity 31s ago)` (était `5m TTL`) |
| Échecs de cache | 16 (était 15) ; cause affichée : « cache scope or TTL changed, usage-limit state changed » |
| Jetons réécrits | 6,4 M (était 5,9 M) : **environ 500 000 pour ce seul échec** |
| Coût estimé | 127,87 $ (était 116,02 $) |

Ce que cela tranche :

- ✅ Le réglage est **honoré en usage supplémentaire** sur un abonnement.
- ✅ Il s'applique à la **session en cours**, sans relancer Claude Code.
- ⚠️ **Changer la durée coûte une réécriture complète** de la conversation, une fois : le cache de 5 min
  n'est pas réutilisé par le cache d'1 h. À poser en début de session, pas au milieu d'une conversation
  longue. (La doc ne le dit pas ; `/usage` le donne comme cause, et le compteur d'échecs a bien pris + 1.)

Restent non vérifiés : le prix réel des écritures en usage supplémentaire, et le comportement en session
cloud.

## ⭐ Ajout du 21/11/2026 : sous-agents passés à 1 h aussi (décision d'Eliott)

Décision d'Eliott, 21/11/2026 : « OUI au cache prompt d'1h et pour tous, sous-agent compris ». Elle **remplace la
recommandation** « Sous-agents laissés à 5 min » de la section « Ce qu'il faut en retenir » ci-dessus, qui reste
écrite pour l'historique.

Réglage posé le 21/11/2026 sur le même poste (Windows, Claude Code 2.1.328 d'après la variable `AI_AGENT` de la
session), dans `~/.claude/settings.json`, à côté du réglage du 20/11 :

```json
{ "promptCacheTtl": "1h", "subagentPromptCacheTtl": "1h" }
```

**Pourquoi la recommandation du 20/11 était fausse pour nous** (raisonnement, pas mesure) : les sous-agents du
projet L18 n'enchaînent pas leurs appels sans pause. Ils attendent régulièrement plus de 5 minutes : un test
dans un navigateur (1 à 5 min), la file d'attente du navigateur partagé entre deux agents, une sonde. Et un
agent repris par `SendMessage` repart avec tout son contexte : le 21/11, un agent d'étude a été relancé avec
environ 400 000 jetons de contexte. À 5 min, chacune de ces attentes fait réécrire tout ce contexte au tarif
d'écriture.

**Documenté** (<https://code.claude.com/docs/en/prompt-caching.md>, relu à la main le 21/11/2026) :

- Les sous-agents, les workflows, les forks, la compaction et les titres de session sont dans le groupe
  « everything else » : **5 min par défaut, même sur un abonnement dans le forfait**, tant que
  `subagentPromptCacheTtl` (ou `CLAUDE_CODE_SUBAGENT_PROMPT_CACHE_TTL`) n'est pas posé.
- Un sous-agent ne lit pas le cache de la session parente (préfixe différent) ; un fork, si. Un sous-agent
  repris peut relire le cache qu'il avait chauffé, s'il n'a pas expiré.
- **Changer de modèle** (`/model`) invalide tout le cache de la conversation : chaque modèle a le sien. Constaté
  le 21/11 : passage de Fable 5.2 à Opus 5.5 au milieu d'une session longue, donc une relecture complète sans
  cache à la réponse suivante (non mesuré dans `/usage`).
- Sur Opus 5.5 et Fable 5.1 et suivants, avec un abonnement, changer l'effort ne casse plus le cache.

**Non vérifié** :

- Si un sous-agent **déjà en cours** au moment du réglage passe à 1 h, ou seulement les suivants. La doc dit que
  la plupart des réglages sont relus à chaud, sans le dire pour celui-ci.
- `/usage` ne montre que la conversation principale (« Prompt cache (main) ») : il ne dit pas la durée du
  cache des sous-agents. Contrôle possible : le champ `usage.cache_creation` (`ephemeral_1h_input_tokens`)
  dans le transcript JSONL d'un sous-agent.
- Le gain réel : à mesurer sur la facture d'un jour de travail par agents, avant et après.
