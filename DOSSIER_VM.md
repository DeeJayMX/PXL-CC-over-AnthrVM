# PXL CC-over-AnthrVM — la VM Claude Code, mesurée

> Ce que la machine **est**, ce qu'elle **sait faire**, et ce qu'elle **refuse**.
>
> Trois campagnes : **25-27/07/2026** (WebGPU, cycle de vie) et **01/08/2026** (GitHub, réseau,
> outillage). Tout ce qui suit est **mesuré depuis l'intérieur**, sondes à l'appui — sauf
> mention explicite. Les sondes sont dans `probes/`, rejouables.

⚠️ **Une VM n'est pas l'autre.** Le silicium, les ports du proxy et les révisions d'outils
changent d'une session à l'autre (§1, §3). **Relancer `probes/vm_survey.sh` en début de
session** plutôt que de faire confiance à un chiffre d'ici. Toute divergence est un fait
nouveau : le mesurer, le dater, l'ajouter — jamais mettre à jour ce dossier de mémoire.

---

## 1. La machine

| | Mesuré |
|---|---|
| Hyperviseur | **Firecracker microVM** (`firecracker-init` dans `/proc/cmdline`) |
| Kernel | **6.18.5** x86_64, `SMP PREEMPT_DYNAMIC` |
| Cœurs · RAM | **4** · **15 Go** |
| CPU | Intel Xeon — ⚠️ **le modèle change** (voir ci-dessous) |
| Disque | ⚠️ `df` affiche 252 Go et **30 Go libres** : le quota est le chiffre *libre*, pas la taille |
| Horloge | UTC |
| Localisation | **indéterminable de l'intérieur** — IP-echo refusé (§3), metadata cloud bloquée. Indice : Firecracker + credentials AWS injectés ⇒ *très probablement* AWS, région inconnue. **Non confirmé.** |

> ⭐ **Le CPU n'est pas stable d'une session à l'autre.** Xeon **@2,80 GHz** les 25-27/07,
> Xeon **@2,10 GHz** le 01/08 — AVX-512 présent dans les deux cas (13 jeux).
>
> **Conséquence directe, et elle mord** : les **fps absolus** du banc SVT-JPEG-XS de
> `PXL-StageBox` (référence 54,3 fps) **ne sont pas reproductibles** d'une session à l'autre.
> Seuls les **rapports** le sont. C'est ce qui justifie *a posteriori* la méthode de la
> **référence intercalée entre chaque variante** — adoptée là-bas pour une autre raison (le
> cache pollué par un rebuild complet), elle protège en fait aussi de ça.
> ⇒ **Ne jamais comparer une mesure de perf à une mesure d'une autre session sans référence
> réintercalée dans la même VM.**

---

## 2. ⭐ Le cycle de vie — et la correction du 01/08

### Ce qui a été mesuré les 26-27/07

| Fait | Mesure |
|---|---|
| Recyclage après inactivité | **~3 min** après la fin du dernier tour (mort bracketée 08:47:54-08:48:24 pour un tour fini ~08:45) |
| Process **détaché** (`nohup`, hors harnais) | **tué en pleine exécution** au recyclage — ne protège pas |
| Tâche **suivie** (`run_in_background`) | **maintient la VM en vie** : 720/720 incréments/5 s sans un seul trou, **1 h complète** sur la même VM, sans message humain. La complétion réveille la session |
| Réveil programmé (`send_later`) | tiré à la seconde, session ressuscitée sans message humain |
| Nouveau message après idle | **VM neuve** (boots observés : 08:28, 08:43, 08:52, 08:58) — transition invisible, boot Firecracker ~ms |
| Scratchpad `/tmp/claude-0/<session>/scratchpad` | **persistant** à travers les recyclages (fichiers du 19/07 toujours là le 27) |
| Conversation | persistante côté serveur — le fil traverse les VM |

Doc officielle (seule source non mesurée) : « *Cloud sessions stop after a period of inactivity
and the underlying environment is reclaimed* » — durée non publiée ; la mesure la fixe à ~3 min
sans tâche suivie.

### 🔴 Ce que le 01/08 corrige

La note du 27/07 affirmait : *« Repo workdir — **re-cloné frais à chaque VM** (~5 s post-boot)
⇒ tout commit non poussé est PERDU »*. **Faux, au moins le 01/08.**

Mesure (VM bootée à 18:32:10 UTC, relevé à 18:39) :

| Indice | Valeur | Ce qu'il prouve |
|---|---|---|
| `mtime` de `/home/user` | **17:16:22** — 76 min **avant** le boot | le répertoire n'a pas été recréé |
| `mtime` de `*/.git` | 18:32:15 — boot **+5 s** | une opération git tourne bien à +5 s… |
| Entrées de reflog **antérieures au boot** | **3 à 6 par clone**, dont des commits faits à 18:00 UTC | …mais ce n'est **pas un clone** : un clone frais aurait un reflog vide |

⇒ **Le workdir a survécu au recyclage.** L'opération de boot+5 s est un **rafraîchissement**
(fetch/reset), pas un `git clone`. La note d'origine avait vu la bonne horloge et **inféré** la
mauvaise opération.

> ⚠️ **Cela ne change PAS la règle pratique — et c'est important.** Un seul recyclage observé,
> dans une seule session ; la persistance peut être propre au volume de *cette* session, et une
> session *nouvelle* repart certainement d'un clone frais. La doc annonce toujours un
> environnement « reclaimed ».
> ⇒ **« Push = survie » reste la règle.** Ce qui change est le *diagnostic*, pas la *discipline* :
> ne pas conclure « mon travail est perdu » sur la seule vue d'un git à boot+5 s — vérifier le
> reflog (`probes/vm_survey.sh`).

### Les règles qui en découlent

1. 🔴 **Push = survie.** Tout livrable est committé **et poussé** dans le tour qui le produit.
2. **Travail long dans un tour** : `run_in_background` (tâche suivie). **Jamais** `nohup`/détaché
   pour quelque chose qui compte — le recyclage le tue en vol.
3. **Travail long hors tour** (nightly, veille) : Routines/scheduler côté serveur — le seul
   mécanisme qui survit à la mort du conteneur.
4. **Diagnostic d'identité** : `probes/vm_survey.sh --canary` en début de session. Le canari
   présent ⇒ workdir survivant ; absent ⇒ VM neuve.
5. Le **scratchpad** sert de boîte noire trans-VM (logs d'expérience, artefacts de session).

---

## 3. Le réseau — un proxy qui n'est pas qu'un proxy

Tout l'egress passe par `HTTPS_PROXY` (**port aléatoire par session** : 42041 le 01/08).
CA bundle en `/root/.ccr/ca-bundle.crt`, `NODE_EXTRA_CA_CERTS` déjà pointé dessus.

| Cible | Résultat mesuré |
|---|---|
| Hôte **hors allowlist** (`mpv.io`, `api.ipify.org`) | `curl: (56) **CONNECT tunnel failed, response 403**` |
| Hôte de la `noProxy` (pypi, npm, crates.io, proxy.golang, anthropic.com) | **direct, HTTP 200** — jamais proxifié |
| **Metadata cloud** `169.254.169.254` | **HTTP 403** — d'où l'impossibilité de localiser la VM |
| ⭐ `"$HTTPS_PROXY/__agentproxy/status"` | **JSON d'introspection** : `enabled`, `selective`, `toolScoped`, `noProxy`, `recentRelayFailures` |

> ⭐ **`__agentproxy/status` est l'outil de diagnostic à connaître.** Devant un échec TLS ou un
> 403/405/407 inexpliqué, il dit si le proxy est en cause **avant** qu'on suspecte son code.
> `recentRelayFailures` journalise les échecs récents. **Ne jamais désactiver la vérification
> TLS ni retirer `HTTPS_PROXY` pour contourner** — c'est traiter le symptôme.

> ⭐ **Le proxy réécrit les réponses de l'API GitHub.** `GET https://api.github.com/zen` ne rend
> pas du GitHub mais :
> ```json
> {"message":"This GitHub API path is not available: sessions are bound to their
>  configured repositories. Use repository-scoped endpoints (repos/{owner}/{repo}/...)."}
> ```
> Ce n'est donc pas un simple tunnel : c'est un **point d'application de politique**, qui
> connaît le périmètre de la session. Retenir la formulation — elle explique le §4.

---

## 3 bis. ⭐ Rejoindre le tailnet PXL depuis la VM — mesuré le 25/09

*Première sortie de la VM vers **notre** réseau. Mesuré le 25/09/2026, kernel 6.18.44, VM neuve
(canari absent). Cas d'usage : piloter le Pi `pxl-matrixled` depuis la session. Recette
rejouable : `pxl-ledmatrix/scripts/claude_tailnet.sh`.*

| Fait | Mesure |
|---|---|
| Serveurs Tailscale (`login.tailscale.com`, `pkgs.tailscale.com`) | ✅ joignables par le proxy HTTPS (302 / 200) |
| Installation | binaires statiques `tailscale_<ver>_amd64.tgz` depuis `pkgs.tailscale.com/stable/` → `/usr/local/bin` (1.102.4 ce jour). Pas d'apt nécessaire |
| `/dev/net/tun` | présent — mais **userspace-networking** retenu : pas de route, pas de root réseau à négocier |
| Auth | `TS_AUTHKEY` en **variable de l'environnement cloud** (jamais dans le chat), clé éphémère taguée, `--state=mem:` |
| Transport | **DERP uniquement** (`direct connection not established`) — pas d'UDP en sortie. DERP Paris, ~115 ms de ping |
| Tailscale SSH (`tailscale ssh user@nœud`) | ✅ fonctionne, pas de clé à gérer ; les users sont ceux permis par la politique `ssh` des ACL |
| TCP vers un port applicatif | ✅ par le SOCKS5 de `tailscaled` (`--socks5-server=localhost:1055`) ou `tailscale nc` |

**Ce que ça change.** Le §7 dit « joindre un hôte hors allowlist : 403 » — **toujours vrai pour
Internet**. Mais un nœud du tailnet est joignable, parce que tout le trafic Tailscale ressort en
HTTPS vers les relais DERP, qui sont, eux, autorisés. Le mur n'est pas contourné, il est traversé
par un hôte légitime.

### Les pièges, déjà payés

1. 🔴 **`NO_PROXY` de la VM contient `100.64.0.0/10`** — la plage CGNAT de Tailscale. Or
   **curl applique `NO_PROXY` même à un proxy passé en option** (`--socks5-hostname`) : pour une IP
   `100.x`, il ignore le SOCKS, part en direct, et **timeout** — ce qui ressemble trait pour trait
   à un refus ACL. Remède : `curl --noproxy '' --socks5-hostname localhost:1055 …`. Un nom
   MagicDNS en `*.ts.net` n'est pas concerné (hors `NO_PROXY`), d'où un 443 qui passe quand le
   8080 « ne passe pas ». *Voir errata 6.*
2. **`tailscaled` = tâche suivie** (`run_in_background` sur `tailscaled` en avant-plan), jamais
   `nohup` — §2 règle 2. Et `--state=mem:` + clé éphémère : le nœud disparaît du tailnet avec la VM.
3. **`tailscale ssh` n'accepte pas les options `-o` d'OpenSSH devant la cible** — il affiche son
   aide, ce qui se lit facilement comme un échec de connexion. L'appeler nu : `tailscale ssh user@nœud 'cmd'`.
   *Voir errata 7.*
4. **`tailscale nc` sans données à envoyer rend la main aussitôt** (EOF sur stdin) : « rien reçu »
   ne prouve pas que le port est fermé. Garder stdin ouvert : `(printf 'GET / HTTP/1.0\r\n\r\n'; sleep 5) | tailscale nc …`.
5. **Diagnostic ACL sans deviner** : sur le nœud cible, `tailscale debug netmap` → `PacketFilter`
   donne les règles **reçues** (sources × ports). C'est ce qui a disculpé l'ACL le 25/09.

---

## 4. ⭐ GitHub : deux couches d'application, et ce qu'elles refusent

Il n'y a **pas de `gh` CLI**. Deux chemins seulement, et **ils n'ont pas les mêmes droits** :

| Chemin | Ce que c'est |
|---|---|
| **Relais git** | `http://local_proxy@127.0.0.1:<port>/git/<owner>/<repo>`, injecté en `--global` par un `url.<…>.insteadOf https://github.com/`. Porte les identifiants ; `git remote -v` ne montre jamais de token |
| **Serveur MCP GitHub** | outils `mcp__github__*` pour l'API (PR, issues, fichiers, CI) |

### Ce qui passe, ce qui ne passe pas — **mesuré le 01/08**

| Opération | Verdict |
|---|---|
| `clone` / `fetch` / `pull` | ✅ |
| `push` — **création** d'une branche distante | ✅ |
| `push` — **mise à jour** d'une branche existante | ✅ |
| 🔴 `push --delete` — **suppression d'une ref** | ❌ **403** sur le POST `receive-pack` (l'annonce `GET` passe pourtant : le refus est tardif) |
| 🔴 **Création d'un dépôt** (`POST /user/repos`) | ❌ **403 « Resource not accessible by integration »** |
| Lecture/écriture de fichiers, PR, issues, CI via MCP | ✅ (dans le périmètre) |
| `delete_branch` dans le MCP | ❌ **l'outil n'existe pas** (il y a `create_branch`, `delete_file`, rien sur les refs) |

> ⚠️ **Deux couches, à ne pas confondre** — je les ai confondues le 01/08 (errata 2) :
> 1. **le proxy de session**, qui impose le *repo-scoping* (§3) et refuse tout chemin d'API non
>    scopé — c'est *structurellement* ce qui interdit `POST /user/repos`, hors périmètre par
>    construction ;
> 2. **les permissions de l'App GitHub**, dont vient le message *« not accessible by
>    integration »* effectivement reçu.
>
> Le message observé est celui de GitHub, donc l'appel a probablement porté jusque-là — mais
> **la conclusion opérationnelle est la même dans les deux cas, et elle est définitive** :
> créer un dépôt ou supprimer une branche **n'est pas faisable depuis la session**. Ça demande
> une action humaine dans l'UI GitHub. Ne pas y passer du temps.

**Périmètre — le second verrou, et il enferme.** La session est liée à une liste de dépôts
fixée **au démarrage de la VM**.

> 🔴 **Un dépôt ne peut pas être attaché à une session déjà lancée** (rapporté par Eliott le
> 01/08 ; non vérifié de l'intérieur, `add_repo` n'ayant pas été appelé). L'outil `add_repo`
> existe et sa description annonce l'inverse — **ne pas s'y fier**.
>
> **Conséquence, et c'est le piège** : les deux verrous se referment l'un sur l'autre. On ne peut
> pas créer un dépôt depuis la session ; et le dépôt créé à la main pendant la session **reste
> hors d'atteinte jusqu'à la session suivante**. Il n'existe donc **aucune séquence** qui, en une
> session, part de rien et aboutit à du contenu poussé dans un dépôt neuf.
>
> ⇒ **Le contournement** : écrire le contenu sur une **branche dédiée d'un dépôt déjà attaché**,
> partant de `main` et n'ajoutant que le dossier — son diff contre `main` *est* le futur dépôt.
> L'extraction se fait à la session suivante. C'est ce qui a été fait ici, et c'est aussi
> l'histoire de `PXL-StageBox`, né sur une branche de `pxl-airlink`.

**Contournement praticable quand la suppression de branche est refusée** : pousser un commit qui
vide la branche de son contenu. L'arbre redevient identique à `main`, l'historique reste. C'est
ce qui a été fait sur `pxl-airlink` le 01/08.

---

## 5. Outillage préinstallé

| Présent | Absent (et ce qu'on fait à la place) |
|---|---|
| `git`, `make`, `cmake`, `gcc`, **`clang` 18** | **`gh`** → MCP GitHub (§4) |
| `node` 22 (`/opt/node22`), `python3`, `rustc`, `go` | **`ffmpeg`** en PATH → un binaire existe sous `/opt/pw-browsers/ffmpeg-*` |
| **`docker`** | **`aarch64-linux-gnu-gcc`** → ⭐ voir ci-dessous |
| Chromium + Playwright (§6) | **`qemu-aarch64`** → ⇒ **rien d'ARM ne peut être *exécuté*** |

> ⭐ **Compiler pour ARM sans cross-toolchain.** Il n'y a pas de `gcc` croisé, mais **clang est
> nativement multi-cible** :
> ```bash
> clang --target=aarch64-linux-gnu -O3 -march=armv8-a+simd -ffreestanding -c f.c -o f.o
> llvm-objdump-18 -d f.o
> ```
> `arm_neon.h` et `stdint.h` viennent du *resource dir* de clang : aucun sysroot requis tant que
> le fichier est autonome. **Validé le 01/08** sur les deux kernels NEON de `PXL-StageBox` —
> compilés, désassemblés, `ld2`/`umaxp` vérifiés dans la sortie.
>
> ⚠️ **Mais sans `qemu-user`, l'exactitude reste invérifiable.** On peut prouver que ça
> *compile* et lire l'assembleur ; on ne peut pas prouver que ça *calcule juste*. C'est
> exactement la limite que `PXL-StageBox` consigne (« bit-exact non prouvé »).

---

## 6. Navigateur, WebGPU, WebCodecs

**Chromium 141.0.7390.37** préinstallé, Playwright configuré (`PLAYWRIGHT_BROWSERS_PATH=/opt/pw-browsers`,
`PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1`). **Ne pas lancer `playwright install`.**

| Capacité | Verdict mesuré (25-26/07) |
|---|---|
| **WebGPU** | ✅ via **SwiftShader** (adapter « google / swiftshader », Vulkan logiciel). Pipeline compute WGSL complet validé, readback correct, textures `r8unorm`/`rg8unorm` 1080p |
| **WebCodecs — VP9, AV1** | ✅ décodeurs logiciels |
| **WebCodecs — H.264/HEVC** | ❌ build sans codecs propriétaires, aucun matériel |
| Allocation « VRAM » | 1 500 slots NV12 1080p (**~4,7 Go**) sans OOM — la « VRAM » **est** la RAM du conteneur |

### Les pièges, déjà payés

1. 🔴 **Contexte sécurisé obligatoire** : `navigator.gpu` **et** `VideoDecoder` sont **absents**
   sur `about:blank` et `data:`. Servir la page sur `http://127.0.0.1:<port>`.
2. 🔴 **Chromium hérite de `HTTPS_PROXY`** et route `127.0.0.1` à travers ⇒ `goto` pendu.
   Lancer avec `proxy: {server: 'direct://'}` (Playwright) ou `--no-proxy-server`.
3. **Flags WebGPU logiciel** : `--enable-unsafe-webgpu --enable-features=Vulkan
   --use-webgpu-adapter=swiftshader --no-sandbox`.
4. `--force-gpu-mem-available-mb` **ne plafonne pas** les allocations WebGPU (testé à 512 Mo :
   4,7 Go alloués quand même). Pour simuler la rareté VRAM ⇒ crochets applicatifs, pas un flag.
5. ❌ **Corrigé le 01/08** : la note d'origine prescrivait
   `executablePath: '/opt/pw-browsers/chromium-<rev>/chrome-linux/chrome'`, à ajuster à chaque
   changement de révision. **Inutile** : `/opt/pw-browsers/chromium` est un **lien symbolique
   direct vers le binaire**. Utiliser ce chemin — il est stable.

6. 🔴🔴 **LA PRÉSENTATION D'UN CANVAS WEBGPU EST HORS DE PORTÉE — et elle PERD LE DEVICE.**
   *Mesuré le 28/08, sonde rejouable : `probes/webgpu_canvas_probe.mjs`.*

   | Épreuve | Résultat |
   |---|---|
   | compute WGSL + `copyTextureToBuffer` + `mapAsync` | ✅ **fonctionne** (c'est le §6 déjà connu) |
   | canvas **2D** ordinaire, rempli en vert, capturé | ✅ **0,255,0** — témoin sain |
   | canvas **WebGPU**, clear rouge par render pass, capturé | ❌ **rien** — le fond de page traverse |
   | `configure()` puis `getCurrentTexture()` en boucle, **sans aucun rendu** | ❌ **`device.lost`** : « a valid external Instance reference no longer exists » |

   La dernière ligne est la plus importante : **aucun code applicatif n'est en cause**. Il
   suffit de *présenter* un canvas WebGPU pour perdre le device. Et une fois le device perdu,
   **WebGPU n'erreure pas — il ignore silencieusement les commandes** : un banc peut compter
   des centaines d'images « décodées » sur un GPU mort, zéro image jetée, écran figé.

   *Revérifié le 28/08 sous le VRAI Google Chrome 152 : **identique**. Ce n'est donc pas un
   défaut du build Chromium préinstallé, mais bien SwiftShader/headless.*

   **Ce que ça impose à un banc dans cette VM :**
   - ✅ prouvable : tout ce qui se relit par `copyTextureToBuffer` + `mapAsync` ;
   - ❌ non prouvable : tout ce qui passe par **l'affichage** d'un canvas WebGPU ;
   - ⚠️ toujours brancher `device.lost` et le faire **échouer le banc**, sinon le compteur ment ;
   - ⚠️ un témoin doit vivre dans une **page séparée** : la perte du device casse la composition
     de toute la page, un canvas 2D témoin ressort blanc lui aussi.

   **Trois hypothèses réfutées avant celle-là** (elles reviendront, elles sont plausibles) :
   *(a)* l'adaptateur `GPUAdapter` collecté par le GC — le garder en vie ne change rien ;
   *(b)* le monde d'exécution séparé de Playwright — l'échec se produit aussi depuis le monde
   principal de la page ; *(c)* le churn de tampons (13 créés/détruits par image) — les rendre
   persistants ne change rien non plus. *Chacune coûtait un aller-retour ; seule la sonde
   d'isolement a tranché.*

7. ⭐ **Google Chrome (le vrai) S'INSTALLE — et il apporte le H.264 en WebCodecs.**
   *Mesuré le 28/08, en deux temps : la première tentative a échoué, Eliott a ouvert
   l'environnement, la seconde est passée. **Les deux moments sont vrais** — c'est la
   politique réseau qui a changé entre les deux, pas le constat.*

   ```bash
   curl -sSL -o chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
   dpkg -i chrome.deb || { apt-get update -qq && apt-get -f install -y; }
   /opt/google/chrome/chrome --version      # → Google Chrome 152.0.7977.64
   ```
   ⚠️ Le `apt-get update` n'est PAS optionnel : sans lui, `apt-get -f install` échoue sur un
   index périmé (`404 Not Found` sur `libegl-mesa0`) et Chrome reste à moitié installé.

   **Ce qu'il change, mesuré** (`VideoDecoder.isConfigSupported`, comparé côte à côte) :

   | | Chromium préinstallé | **Google Chrome 152** |
   |---|---|---|
   | H.264 décodage | ❌ | ✅ |
   | H.264 **encodage** | ❌ | ✅ |
   | HEVC | ❌ | ❌ (Chrome Linux ne l'embarque pas) |
   | VP9 · AV1 | ✅ | ✅ |
   | canvas WebGPU affiché | ❌ | ❌ **identique** — voir piège 6 |

   ⇒ **le récepteur H.264 de TurboHQ devient testable en VM**, ce qui n'était pas le cas.
   ⇒ mais **le piège 6 n'est PAS un problème de build** : le canvas WebGPU ne se composite
   pas davantage sous le vrai Chrome. C'est bien SwiftShader/headless, pas Chromium.

   Bascule dans nos bancs : `PXL_BROWSER=chrome node <banc>` (`webgpu_harness.mjs`).

   ⚠️ **Ça ne survit pas au recyclage** — comme tout ce qui vit hors du workdir. La recette
   ci-dessus est à rejouer à chaque session qui en a besoin.

### La division du travail

| Étage | Où | Quoi |
|---|---|---|
| Logique pure | VM (node) | maths, bookkeeping, property tests, simulateurs |
| Fonctionnel complet | VM (Chromium headless, média **VP9/AV1** basse rés) | comportement — **pas** la performance |
| Vérité physique | **Machine locale** | H.264/HEVC, GPU réel, NVDEC, timings, 4K |

---

## 7. Ce qui est hors d'atteinte, définitivement

| | Pourquoi |
|---|---|
| Créer un dépôt · supprimer une branche | §4 — action humaine dans l'UI |
| **Attacher un dépôt à une session en cours** | §4 — le périmètre est figé au démarrage de la VM ; il faut une session neuve |
| Exécuter du code ARM | pas de `qemu-user` (§5) |
| Mesurer une perf comparable entre sessions | le CPU change (§1) |
| Joindre un hôte hors allowlist | 403 CONNECT (§3) — *vrai pour Internet ; un nœud de notre tailnet, lui, est joignable par DERP (§3 bis, 25/09)* |
| Localiser la VM | metadata bloquée (§1, §3) |
| **Autoriser un serveur MCP en OAuth** | le flux est interactif ; en session non-interactive c'est impossible. Vu le 01/08 sur le connecteur Canva. ⇒ passe par les réglages claude.ai de l'utilisateur |
| Plafonner la VRAM par un flag Chromium | §6 piège 4 |
| **Afficher un canvas WebGPU** (et donc tester un rendu à l'écran) | §6 piège 6 — présenter perd le device |
| **HEVC en WebCodecs** | §6 piège 7 — même le vrai Chrome ne l'embarque pas sous Linux |

---

## 8. Errata

*Les erreurs commises pendant l'exploration, avec leur raison. Ne jamais en supprimer une pour
« nettoyer » : elles documentent des raisonnements qui seront refaits.*

1. ❌ **« Le workdir est re-cloné frais à chaque VM. »** (note du 27/07) Mesuré le 01/08 : le
   clone **survit**, reflog intact, entrées antérieures au boot. L'erreur venait d'une
   **inférence sur une horloge** : une opération git à boot+5 s a été lue comme un `clone` alors
   que c'est un rafraîchissement. **Leçon : une opération observée par son timing n'est pas
   identifiée pour autant.** La règle pratique (« push = survie ») ne bouge pas pour autant —
   elle repose sur la doc et sur le risque, pas sur ce diagnostic.

2. ❌ **« L'App GitHub n'a pas le droit de créer des dépôts, c'est une permission de compte. »**
   (01/08, annoncé avant de mesurer) Incomplet : il y a **deux couches**, et le proxy de session
   refuse *structurellement* tout chemin d'API non scopé au dépôt — ce qui est une raison
   suffisante à elle seule. Le message reçu venait bien de GitHub, mais l'explication donnée
   était monocouche. **Leçon : ne pas expliquer un refus par la première cause plausible quand
   l'environnement en empile deux.**

3. ❌ **« `add_repo` étend le périmètre en cours de route. »** (01/08, écrit d'après la
   description de l'outil, avant vérification) Faux : le périmètre est figé au démarrage de la
   VM — un dépôt créé pendant la session reste inatteignable jusqu'à la suivante. **Leçon : la
   description d'un outil décrit son intention, pas la politique de l'environnement qui
   l'héberge.** Ce dossier entier est né de ce piège : le plan « je crée le dépôt puis je
   l'attache » était mort deux fois plutôt qu'une.

4. ❌ **`executablePath` versionné pour Chromium** (note du 25/07) — le lien stable
   `/opt/pw-browsers/chromium` existe. Voir §6.5.

5. ❌ **Sonde `vm_survey.sh`, premier jet, trois défauts** dont un instructif : sous
   `set -o pipefail`, `curl … | grep` **échoue même quand `grep` trouve**, parce que `curl` sort
   56 sur un CONNECT refusé et que `pipefail` propage l'échec le plus à droite… qui n'est pas
   celui qu'on regarde. Le `||` de secours se déclenchait **en plus** du résultat correct, et la
   sonde affichait les deux verdicts à la fois. **Leçon : sous `pipefail`, capturer avant de
   filtrer quand la commande de gauche a le droit d'échouer.** (Les deux autres : `$HOME` vaut
   `/root` et non le workdir ; f-string Python avec guillemets doubles imbriqués.)

6. ❌ **« Le port 8080 du Pi est bloqué par l'ACL Tailscale. »** (25/09) Annoncé sur un timeout
   curl ; l'ACL était correcte (tags `tag:pxl-vm` → `tag:pxl-dev`, port 8080 présent dans le
   `PacketFilter` reçu par le Pi). Cause réelle : `NO_PROXY` de la VM couvre `100.64.0.0/10`, et
   curl l'applique même au SOCKS passé en option — la requête n'a jamais traversé Tailscale.
   Indice négligé : le 443 du même Pi passait, **par son nom `*.ts.net`**. **Leçon : un timeout
   n'est pas un refus ; avant d'accuser la politique distante, vérifier que le paquet a bien pris
   le chemin prévu** — ici, la variable d'environnement locale mentait plus tôt que l'ACL.

7. ❌ **« Le Pi n'a pas Tailscale SSH, seulement OpenSSH. »** (25/09) Conclu parce que
   `tailscale ssh -o … user@nœud` « échouait » — il affichait en fait son aide (options `-o`
   refusées), puis un `ssh` OpenSSH via `tailscale nc` tombait bien sur `Permission denied`.
   Appelé nu, `tailscale ssh root@pxl-matrixled` passait du premier coup. **Leçon : lire la sortie
   d'un outil avant de la classer en échec — une page d'aide n'est pas un refus.**

---

## 9. Sources

**Mesures** — `probes/vm_survey.sh` (01/08) · `probes/webgpu_probe.mjs`, `probes/vram_probe.mjs`
(25-26/07) · **`probes/webgpu_canvas_probe.mjs` (28/08)** · relevés de cycle de vie des 26-27/07, repris de
`PXL-Tape/v3/tests/investigations/note_vm_lifecycle.md`.

**Documentation** — [Claude Code on the web](https://code.claude.com/docs/en/claude-code-on-the-web)
(environnements, politiques réseau, triggers, sources) · `/root/.ccr/README.md` (proxy, dans la VM).

**Documents PXL liés** — `PXL-Tape/v3/tests/investigations/note_vm_lifecycle.md` et
`note_vm_webgpu.md` (les notes d'origine, dont ce dossier est la reprise et la correction) ·
`PXL-StageBox/jpegxs-arm/README.md` (le banc dont le §1 explique la non-reproductibilité).
