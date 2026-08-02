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
2. ⚠️ **Attacher un dépôt à une session déjà lancée l'était aussi** — le périmètre GitHub
   semblait figé au démarrage de la VM. **Ce verrou-là est tombé le 02/08** (voir plus bas) :
   il a tenu le temps d'écrire ce dossier, pas au-delà.

⇒ **Aucune séquence ne part de rien et n'aboutit à du contenu poussé dans un dépôt neuf en une
seule session cloud.** Le contournement — écrire sur une branche dédiée d'un dépôt déjà attaché,
dont le diff contre `main` *est* le futur dépôt — a servi ici, et c'est aussi l'histoire de
`PXL-StageBox`, né sur une branche de `pxl-airlink`.

## Contenu

| | |
|---|---|
| [`DOSSIER_VM.md`](DOSSIER_VM.md) | **Le dossier.** Machine, cycle de vie, réseau/proxy, GitHub, outillage, navigateur, errata. Point d'entrée. |
| [`probes/vm_survey.sh`](probes/vm_survey.sh) | **À lancer en début de session.** Relevé d'état + canari de survie du workdir. |
| [`probes/webgpu_probe.mjs`](probes/webgpu_probe.mjs) | WebGPU (adapter, compute WGSL, textures) + inventaire WebCodecs |
| [`probes/vram_probe.mjs`](probes/vram_probe.mjs) | limites d'allocation, ring NV12 1080p par paliers jusqu'à OOM |
| [`probes/tunnel_probe.py`](probes/tunnel_probe.py) | **egress réel** : quels ports sortent, interception TLS, verdict Cloudflare Tunnel / Tailscale |
| [`probes/ui_probe.mjs`](probes/ui_probe.mjs) | **piloter une interface** : servir, manipuler au pointeur/clavier, relire côté serveur, capturer |

```bash
bash probes/vm_survey.sh --canary
python3 probes/tunnel_probe.py            # + --download pour tenter un vrai quick tunnel
npm i playwright && node probes/ui_probe.mjs
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

**🔴 `add_repo` marche — la prémisse de ce dépôt est tombée.** Le 02/08, **deux dépôts ont été
attachés en cours de session** et clonés sans encombre (l'un venait d'être rendu public, l'autre
existait déjà, 141 Mo). La conclusion du 01/08 — « le périmètre GitHub est figé au démarrage » —
est donc **caduque pour les dépôts existants**. Le détour d'organisation raconté ci-dessus reste
l'histoire vraie de la naissance de ce dossier, mais **ce n'est plus une contrainte**. Restent
non retestés : la *création* d'un dépôt, et `add_repo` sur un dépôt créé pendant la session.
⇒ *Une conclusion négative se re-mesure avant qu'on bâtisse dessus.*

**Supprimer une branche** reste hors d'atteinte (403 sur le `receive-pack`). Contournement :
pousser un commit qui vide la branche.

**Rien ne sort de la VM sauf par 80 et 443 — et rien n'y entre.** Mesuré le 02/08 : les ports 22,
587, 853, 8080 et 7844 ne répondent pas (silence, pas même un RST) ; seul UDP/53 passe. Et le
proxy **n'est pas contournable en ouvrant une socket** : le TLS est intercepté en transparence,
certificat `O=Anthropic, CN=Egress Gateway SDS Issuing CA`, y compris sur les hôtes de
`no_proxy`. ⇒ **Aucun tunnel n'expose un serveur de la VM** : `cloudflared` (hôte de réservation
en 403 *et* port 7844 muré) ni Tailscale (plan de contrôle, DERP et paquets en 403, pas d'UDP).
C'est un réglage d'**egress de l'environnement** (champ **Network access** : None / Trusted / Full / Custom, sur `claude.ai/code`), pas un problème d'outil — et aucun outil de session ne le modifie.

**En échange, on peut piloter une UI et la regarder.** Servir une page en local, la manipuler au
pointeur et au clavier, vérifier ce que le serveur a reçu, capturer le rendu — et **relire la
capture**. Une console web dont le matériel est ailleurs se valide entièrement ici.

**On peut compiler pour ARM sans cross-toolchain** (`clang --target=aarch64-linux-gnu`), mais
**pas exécuter** — il n'y a pas de `qemu-user`. La correction se prouve, l'exactitude non.

## ⚠️ Statut des chiffres

Tout est mesuré depuis l'intérieur, sondes à l'appui — sauf trois points marqués comme tels dans
le dossier : la **localisation** de la VM (AWS supposé, non confirmé), la **durée de recyclage**
côté doc officielle, et les **deux couches** du refus GitHub (une seule des deux est directement
observée). Le dossier tient une section **Errata** : **huit entrées**, dont six sont des
inférences ou des prescriptions fausses corrigées à la mesure — trois ajoutées le 02/08, dont
une qui invalide la prémisse même de ce dépôt.

Reste explicitement **non mesuré** : si autoriser un hôte dans les réglages d'egress ouvre aussi
ses **ports non standard**. C'est ce qui déciderait du sort de Cloudflare Tunnel.

**Une VM n'est pas l'autre** : relancer `vm_survey.sh` plutôt que citer un chiffre d'ici.
