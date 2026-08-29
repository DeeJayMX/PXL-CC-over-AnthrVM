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
- 🔴 **Tunnels sortants — LE FILTRE A CHANGÉ DE NATURE, et ce fichier l'a annoncé faux pendant
  un mois.** Il disait *« l'egress est restreint à TCP/80, TCP/443, UDP/53 »* (mesuré 02/08),
  ce qui était vrai à cette date. **Mesuré le 19/08** : le filtrage est désormais **par HÔTE**,
  par une passerelle TLS d'Anthropic qui lit le **SNI** et rend un 403 nommant l'hôte refusé
  (`Host not in allowlist: …`). Témoins : `pypi.org` → 200, `example.com` → **403**.
  ⇒ **Le repli DERP-sur-443 ne contourne donc plus rien** : `derp*.tailscale.com:443` est refusé
  au même titre. Le remède n'est pas du code — il faut ajouter `*.tailscale.com` (au minimum
  `controlplane.` + `derp*.` + `log.`) dans **Network egress settings** de l'environnement.
  ⚠️ Et ces réglages **ne sont PAS figés au démarrage** : un ajout fait depuis l'interface WEB
  s'applique en direct aux sessions vivantes (errata 12). Voir § 3 du dossier.
  ⚠️ Cloudflare Tunnel **ne passe pas** (port 7844). Les deux rendent un **plan de contrôle qui
  réussit** avant d'échouer.
  🔴 *Ce fait était mesuré et poussé depuis le 19/08 ; il est resté un mois dans une branche que
  j'avais refusé de fusionner sur un diff lu à l'envers — errata 16.*
- **Remonter le tunnel dans une VM neuve** : `bash tunnel_up.sh [port]` (§3 ter). 🔴 La clé de
  nœud n'est pas persistable — le workdir disparaît, et la versionner publierait un secret.
  C'est `TS_AUTHKEY` qui survit, dans les variables d'environnement de l'environnement Claude
  Code : **claude.ai/code → icône nuage au-dessus de la saisie → roue dentée** (il n'y a ni page
  de réglages ni URL directe, d'où la difficulté à la trouver). 🔴 **Cette boîte n'est pas un
  coffre** — la doc interdit d'y mettre des credentials, ses valeurs sont lisibles par quiconque
  utilise l'environnement. Donc scoper la clé plutôt que la croire cachée : **réutilisable +
  éphémère + taguée**. C'est l'errata 8. ⚠️ `serve`, jamais `funnel`.
- ⚠️ **Une variable d'environnement ne prend effet qu'à la NAISSANCE d'une VM** (mesuré 03/08,
  §3 ter) : rafraîchir en re-provisionne une, ce n'est pas une synchro. En revanche le conteneur
  **persiste entre les invocations** — `uptime` mesuré deux fois le prouve. Et 🔴 **l'ACL d'un
  nœud ne se teste pas depuis ce nœud** : proxy → 502, `--accept-dns=false` → pas de MagicDNS.
  Un échec là n'est pas un refus d'ACL. Policy de référence : `tailscale-policy.hujson`.
- ⭐ **Le tunnel se remonte TOUT SEUL** : hook `SessionStart` → `session_start.sh` (console puis
  tunnel, idempotent, ~10 s à chaud, sort toujours en 0). Deux variables à poser une fois dans
  l'environnement : `TS_AUTHKEY` et `PXL_CONSOLE_MOTDEPASSE` — sans la seconde, le mot de passe
  de la console est tiré au sort à chaque réveil.
- 🔴 **L'entrant ne passe que si le RELAIS HOME est celui des pairs** (mesuré 03/08, §3 ter).
  La VM est aux USA, elle choisit `nyc` ; un pair européen envoie vers `nyc` et rien n'arrive,
  alors que le sortant marche — asymétrie qui ressemble à une ACL et n'en est pas.
  `tunnel_up.sh` force désormais la région la plus peuplée chez les pairs en ligne
  (`TS_DERP_REGION` pour surcharger). ⚠️ `force-prefer-derp` est « until restart ».
- 🔴 **Le port du proxy de session change** quand l'infrastructure redémarre (signe : les MCP se
  déconnectent/reconnectent). `tailscaled` l'a mémorisé au démarrage ⇒ il perd sa sortie et
  meurt. Relancer console **puis** `tunnel_up.sh`. ⚠️ Et `tailscale ping` d'un pair vers la VM
  est soumis à l'ACL : avec une règle `:443` seule, il échoue même quand tout marche — ne pas
  diagnostiquer avec.
- ⚠️ **Un nœud porte DEUX noms** : `HostName` (affiché) et `DNSName` (l'URL). Un suffixe `-1`
  marque une collision ; supprimer l'homonyme rend le `HostName` tout seul mais **pas** le
  `DNSName`, figé à l'enregistrement. Pour le reprendre sur un nœud éphémère : `tailscale
  logout` puis `tunnel_up.sh` — **pas** un rafraîchissement de session, qui recrée la VM et tue
  la console au passage. ⚠️ Et le nœud éphémère meurt avec la VM : relancer console **puis**
  tunnel à chaque réveil, dans cet ordre.
- ⭐⭐ **LA CARTE EST JOIGNABLE DEPUIS LA VM depuis le 29/08** (§ 3 sexies) — elle est taguée
  `tag:pxl-dev` et une règle ouvre **22 · 8710 · 443 · 8443**. `tailscale nc` est le **seul**
  outil qui route le 100.x (userspace-networking : ni `curl` ni le proxy ne le voient), et
  `~/.ssh/config` porte un hôte `pxl-tx` dont le `ProxyCommand` s'en sert.
  🔴 **Trois verdicts, trois causes, et « refusé » est la BONNE nouvelle** : un RST prouve que le
  paquet a atteint la carte (l'ACL passe, rien n'écoute) ; seul un **pendu** est un refus d'ACL,
  Tailscale jetant en silence. Toujours sonder **un port hors règle en contrôle**, sinon les deux
  se confondent en « ça ne marche pas ».
  ⚠️ **Et `timeout … | head` rend le code de `head`** : la première sonde annonçait `rc=0` sur
  cinq ports dont deux étaient dropés — une victoire fausse.
  🔴 **Le SSH reste fermé et le TAG en est la cause** : le bloc `ssh` du tailnet vise
  `autogroup:self`, dont une machine taguée ne fait jamais partie. Il faut une règle `ssh` en
  **`accept`** (jamais `check` — il demande une ré-auth humaine) **et** `tailscale set --ssh`
  sur la carte. 🎯 Ouvrir un port n'allume rien derrière : 443/8443 sont ouverts et **vides**.
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
