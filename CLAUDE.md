# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Nature de ce dépôt

**Dépôt d'exploration, pas de base de code.** Ni build system, ni application, ni tests. Le
sujet est **la VM Claude Code elle-même** : ce qu'elle est, ce qu'elle sait faire, ce qu'elle
refuse. Le livrable est le relevé — [`DOSSIER_VM.md`](DOSSIER_VM.md) — et les trois sondes de
`probes/` qui le rejouent.

Particularité : **ce dépôt décrit l'environnement dans lequel tu tournes peut-être.** Si la
session est une session cloud, les contraintes documentées ici s'appliquent à toi, maintenant.

## Réflexe de début de session

```bash
bash probes/vm_survey.sh --canary
```

Le canari présent ⇒ workdir survivant. Absent ⇒ VM neuve.

## La règle de rédaction, et elle est inhabituelle

⚠️ **Une VM n'est pas l'autre.** Le silicium, les ports du proxy et les révisions d'outils
changent d'une session à l'autre.

> **Toute divergence constatée est un fait nouveau : le mesurer, le dater, l'ajouter — jamais
> « mettre à jour » le dossier.**

C'est un document de mémoire, pas un état courant. Un chiffre daté qui a changé reste
intéressant (il prouve la variabilité) ; le même chiffre écrasé silencieusement ne prouve plus
rien. Corollaire : ne jamais citer un chiffre d'ici comme la vérité de la session en cours —
relancer la sonde.

**La section « Errata » (§8) ne se nettoie pas.** Elle consigne des inférences fausses avec leur
mécanisme ; trois des cinq entrées corrigent une conclusion tirée trop vite d'une observation
juste. Ce sont exactement les raisonnements qui seront refaits. Une erreur corrigée **s'y
ajoute**.

Le dossier sépare partout **mesuré** / **calculé** / **supposé** (⭐ fait porteur · ⚠️ réserve ·
🔴 bloquant). Trois points seulement sont non mesurés et marqués comme tels : la localisation de
la VM, la durée de recyclage côté doc officielle, et la seconde des deux couches du refus GitHub.

## Ce qu'il faut savoir avant de perdre du temps

Détaillé dans `DOSSIER_VM.md` §4 et §7 — les pièges qui coûtent le plus cher :

- 🔴 **Créer un dépôt et supprimer une branche sont hors d'atteinte** depuis une session cloud
  (403). **Attacher un dépôt à une session en cours aussi** : le périmètre est figé au démarrage
  de la VM. Ne pas y passer du temps — ça demande une action humaine, ou un poste local.
  Contournement pour la suppression de branche : pousser un commit qui la vide.
- 🔴 **Push = survie.** Tout livrable est committé *et poussé* dans le tour qui le produit.
  Travail long ⇒ `run_in_background` (tâche suivie, maintient la VM en vie), **jamais**
  `nohup`/détaché — le recyclage le tue en vol.
- **Devant un 403/407/échec TLS inexpliqué** : `curl "$HTTPS_PROXY/__agentproxy/status"` avant
  de suspecter son propre code. Ne jamais désactiver la vérification TLS ni retirer
  `HTTPS_PROXY` pour contourner.
- **Chromium** : contexte sécurisé obligatoire (`http://127.0.0.1:<port>`, pas `about:blank`),
  et Chromium hérite de `HTTPS_PROXY` ⇒ `proxy: {server: 'direct://'}`. Binaire stable :
  `/opt/pw-browsers/chromium` (lien symbolique — ne pas versionner la révision). Ne pas lancer
  `playwright install`.
- **ARM** : `clang --target=aarch64-linux-gnu` compile sans cross-toolchain, mais il n'y a pas de
  `qemu-user` ⇒ **rien d'ARM ne peut être exécuté**. La correction se prouve, l'exactitude non.
- **Aucune mesure de perf n'est comparable entre deux sessions** — le CPU change. Seuls les
  rapports le sont, avec référence réintercalée dans la même VM.

## Documents PXL liés

`PXL-StageBox/jpegxs-arm/README.md` — le banc dont la méthode (référence intercalée) est
justifiée *a posteriori* par le §1 d'ici · `PXL-Tape` — dépôt d'origine des notes.
