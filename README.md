# PXL CC-over-AnthrVM

> **La VM Claude Code, mesurée de l'intérieur.** Ce que la machine est, ce qu'elle sait faire,
> et ce qu'elle refuse — pour arrêter de redécouvrir les mêmes murs à chaque session.
>
> **Statut : dossier d'exploration.** Ni build system, ni application. Le livrable est le
> relevé et les sondes qui le rejouent.

## Origine — et pourquoi le détour

Ce dossier est né sur la branche `claude/cc-over-anthrvm` de `DeeJayMX/PXL-Tape` — là où sont
nées les notes d'origine — et a été extrait ici le 02/08/2026, **depuis un poste local**.

Ce détour n'est pas un caprice d'organisation : c'est la conséquence directe de deux verrous
mesurés dans ce dossier ([`DOSSIER_VM.md`](DOSSIER_VM.md) §4), qui se referment l'un sur l'autre.

1. **Créer un dépôt est impossible depuis la session** — `POST /user/repos` prend un **403**.
2. ~~**Attacher un dépôt à une session déjà lancée l'est aussi**~~ — **infirmé le 02/08**
   (§4 bis, errata 7) : `add_repo` attache bel et bien un dépôt en cours de session. Le verrou
   n'a jamais été mesuré, seulement rapporté, et il a été cru.
   ⭐ **Re-mesuré le 18/08 et confirmé** — trois fois de l'intérieur, clone + register + push
   compris (errata 11). ⚠️ Le résidu qui reste non vérifié est étroit : attacher un dépôt **créé
   pendant** la session. Le récit d'origine reste vrai à sa date, et c'est tout l'intérêt de
   dater.

⇒ Le premier verrou tient : **aucune séquence ne part de rien et n'aboutit à du contenu poussé
dans un dépôt neuf en une seule session cloud** — mais c'est désormais la *création* seule qui
l'interdit, pas l'attachement. Un dépôt créé à la main pendant la session est attachable tout de
suite. Le contournement — écrire sur une branche dédiée d'un dépôt déjà attaché, dont le diff
contre `main` *est* le futur dépôt — a servi ici, et c'est aussi l'histoire de `PXL-StageBox`,
né sur une branche de `pxl-airlink`.

## Contenu

| | |
|---|---|
| [`DOSSIER_VM.md`](DOSSIER_VM.md) | **Le dossier.** Machine, cycle de vie, réseau/proxy, GitHub, outillage, navigateur, errata. Point d'entrée. |
| [`probes/vm_survey.sh`](probes/vm_survey.sh) | **À lancer en début de session.** Relevé d'état + canari de survie du workdir. |
| [`probes/tunnel_probe.sh`](probes/tunnel_probe.sh) | ports ouverts en sortie, UDP, et le verdict Tailscale / Cloudflare Tunnel (`--full` lance les deux clients) |
| [`probes/webgpu_probe.mjs`](probes/webgpu_probe.mjs) | WebGPU (adapter, compute WGSL, textures) + inventaire WebCodecs |
| [`probes/vram_probe.mjs`](probes/vram_probe.mjs) | limites d'allocation, ring NV12 1080p par paliers jusqu'à OOM |

```bash
bash probes/vm_survey.sh --canary
```

## Les résultats à retenir

**Le workdir n'est pas ce qu'on croyait.** La note du 27/07 affirmait qu'il était re-cloné à
chaque VM. Mesuré le 01/08 : il **survit** au recyclage, reflog intact. L'opération vue à
boot+5 s est un rafraîchissement, pas un clone. ⚠️ **La règle ne change pas pour autant —
« push = survie » tient** : un seul recyclage observé, et une session neuve repart certainement
d'un clone frais. Ce qui change est le diagnostic, pas la discipline.

**Le CPU change d'une session à l'autre** (Xeon @2,8 GHz le 27/07, @2,1 GHz le 01/08). ⇒ Aucune
mesure de performance n'est comparable entre sessions sans référence réintercalée. C'est ce qui
justifie *a posteriori* la méthodologie du banc JPEG-XS de `PXL-StageBox`.

**Le proxy n'est pas un tunnel, c'est un point d'application de politique.** Il connaît le
périmètre de la session et **réécrit les réponses de l'API GitHub** hors périmètre. Il expose son
propre diagnostic : `curl "$HTTPS_PROXY/__agentproxy/status"`.

**Un tunnel sortant passe si et seulement s'il sait parler par TCP/443 seul** (02/08). L'egress
est restreint à **TCP/80, TCP/443 et UDP/53** : **Tailscale passe**, mais en relais DERP
uniquement (jamais en pair-à-pair, l'UDP est filtré) ; **Cloudflare Tunnel non**, son plan de
données est cloué sur le port 7844 sans repli. Les deux rendent pourtant un plan de contrôle
verdoyant avant d'échouer — c'est le piège. ⚠️ La politique réseau est un réglage
d'**environnement**, pas une propriété de la VM : elle a déjà divergé entre le 01/08 et le 02/08.

**Deux choses sont définitivement hors d'atteinte** : créer un dépôt, et supprimer une branche
(403 sur le `receive-pack`). Contournement pour la seconde : pousser un commit qui vide la
branche.

**On peut compiler pour ARM sans cross-toolchain** (`clang --target=aarch64-linux-gnu`), mais
**pas exécuter** — il n'y a pas de `qemu-user`. La correction se prouve, l'exactitude non.

## ⚠️ Statut des chiffres

Tout est mesuré depuis l'intérieur, sondes à l'appui — sauf trois points marqués comme tels dans
le dossier : la **localisation** de la VM (AWS supposé, non confirmé), la **durée de recyclage**
côté doc officielle, et les **deux couches** du refus GitHub (une seule des deux est directement
observée). Le dossier tient une section **Errata** : six entrées, dont quatre sont des
inférences fausses corrigées à la mesure.

**Une VM n'est pas l'autre** : relancer `vm_survey.sh` plutôt que citer un chiffre d'ici.
