# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Nature de ce dépôt

**Dépôt d'exploration, pas de base de code.** Ni build system, ni application, ni tests. Le
sujet est **la VM Claude Code elle-même** : ce qu'elle est, ce qu'elle sait faire, ce qu'elle
refuse. Le livrable est le relevé — [`DOSSIER_VM.md`](DOSSIER_VM.md) — et les quatre sondes de
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
mécanisme ; quatre des six entrées corrigent une conclusion tirée trop vite d'une observation
juste. Ce sont exactement les raisonnements qui seront refaits. Une erreur corrigée **s'y
ajoute**.

Le dossier sépare partout **mesuré** / **calculé** / **supposé** (⭐ fait porteur · ⚠️ réserve ·
🔴 bloquant). Trois points seulement sont non mesurés et marqués comme tels : la localisation de
la VM, la durée de recyclage côté doc officielle, et la seconde des deux couches du refus GitHub.

## Ce qu'il faut savoir avant de perdre du temps

Détaillé dans `DOSSIER_VM.md` §4 et §7 — les pièges qui coûtent le plus cher :

- 🔴 **Créer un dépôt et supprimer une branche sont hors d'atteinte** depuis une session cloud
  (403). Ne pas y passer du temps — ça demande une action humaine, ou un poste local.
  Contournement pour la suppression de branche : pousser un commit qui la vide.
- ⭐ **Attacher un dépôt en cours de session, en revanche, marche** (`add_repo`, mesuré 02/08,
  §4 bis). Le dossier a longtemps dit le contraire, sur un rapport non vérifié — c'est
  l'errata 7. ⚠️ **L'invite système continue d'afficher la liste du démarrage** après un
  `add_repo` réussi : elle n'est pas la liste effective. Avant de déclarer un dépôt
  inatteignable, appeler `list_repos`. Un clone à la fois (sinon HTTP 429), délai généreux.
- 🔴 **Push = survie.** Tout livrable est committé *et poussé* dans le tour qui le produit.
  Travail long ⇒ `run_in_background` (tâche suivie, maintient la VM en vie), **jamais**
  `nohup`/détaché — le recyclage le tue en vol.
- **Devant un 403/407/échec TLS inexpliqué** : `curl "$HTTPS_PROXY/__agentproxy/status"` avant
  de suspecter son propre code. Ne jamais désactiver la vérification TLS ni retirer
  `HTTPS_PROXY` pour contourner. ⚠️ Son `recentRelayFailures` a un angle mort — il est resté
  vide sur des connexions pendues (§3 bis, errata 6). Champ vide ≠ pas d'échec.
- **Tunnels sortants** : l'egress est restreint à **TCP/80, TCP/443, UDP/53** (mesuré 02/08,
  `probes/tunnel_probe.sh`). Tailscale passe **en relais DERP seulement** (`--auth-key`,
  l'auth interactive est hors d'atteinte) ; Cloudflare Tunnel **ne passe pas** (port 7844). Tout
  client dont le plan de données ne sait pas se replier sur TCP/443 est mort — ne pas le tester.
  Attention : les deux rendent un **plan de contrôle qui réussit** avant d'échouer.
- **Remonter le tunnel dans une VM neuve** : `bash tunnel_up.sh [port]` (§3 ter). 🔴 La clé de
  nœud n'est pas persistable — le workdir disparaît, et la versionner publierait un secret.
  C'est `TS_AUTHKEY`, dans les variables d'environnement de l'environnement Claude Code, qui
  survit ; le script la consomme. ⚠️ `serve`, jamais `funnel`.
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
