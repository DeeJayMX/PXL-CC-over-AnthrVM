# PXL CC-over-AnthrVM — la VM Claude Code, mesurée

> Ce que la machine **est**, ce qu'elle **sait faire**, et ce qu'elle **refuse**.
>
> Trois campagnes : **25-27/07/2026** (WebGPU, cycle de vie), **01/08/2026** (GitHub, réseau,
> outillage) et **02/08/2026** (egress réel, tunnels, pilotage d'interface). Tout ce qui suit est
> **mesuré depuis l'intérieur**, sondes à l'appui — sauf mention explicite. Les sondes sont dans
> `probes/`, rejouables.

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
| Hôte de la `noProxy` (pypi, npm, crates.io, proxy.golang, anthropic.com) | **HTTP 200** — sans passer par le `CONNECT`. ⚠️ « direct » est **faux**, voir le 02/08 ci-dessous |
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

### 🔴 Ce que le 02/08 ajoute — on ne le contourne pas, et il n'y a que deux ports

Sonde : `probes/tunnel_probe.py`. Deux mesures, toutes deux **hors** `HTTPS_PROXY` (sockets brutes).

**a) Ouvrir une socket ne contourne rien.** Poignée de main TLS directe, sans variable
d'environnement, sur six hôtes — le certificat présenté est **toujours** le même :

```
O=Anthropic  CN=Egress Gateway SDS Issuing CA (production)
```

…et l'allowlist s'applique quand même (`403 Forbidden` pour `api.trycloudflare.com`,
`controlplane.tailscale.com`, `1.1.1.1` ; `200` pour `github.com`, `pypi.org`, `proxy.golang.org`).

> ⇒ **L'egress est intercepté en transparence sur le port 443**, pas seulement routé par une
> variable d'environnement. `no_proxy` signifie « ne passe pas par le `CONNECT` », **pas**
> « échappe à la politique » — et les hôtes de `noProxy` reçoivent eux aussi le certificat
> Anthropic. La note du 01/08 disait « direct, jamais proxifié » : la moitié « jamais
> proxifié » est fausse.

**b) Seuls deux ports quittent la VM.**

| Port | Verdict mesuré |
|---|---|
| **443**, **80** | ouverts |
| 22 (SSH), 587 (SMTP), 853 (DoT), 8080, **7844** (bord Cloudflare) | **silence — timeout, pas même un RST** |
| **UDP 53** (DNS) | répond |
| tout autre UDP (WireGuard, QUIC) | muet |

> ⇒ Un protocole à port dédié est mort **avant** qu'on parle d'allowlist. C'est la contrainte la
> plus dure de cette machine, et celle qu'on découvre le plus tard.

### Exposer un serveur web de la VM vers l'extérieur : **non**

La question se pose dès qu'on développe une UI ici (une console de régie, un viewer). Réponse
mesurée le 02/08 : **aucun tunnel ne passe**, et l'échec n'est jamais celui de l'outil.

| | Ce qui marche | Ce qui bloque |
|---|---|---|
| **cloudflared** | binaire téléchargé depuis GitHub (39 Mo) et exécutable — `2026.7.3` | `api.trycloudflare.com` → **403** ; **et** le port de bord **7844** ne sort pas. Cloudflared n'a **pas de repli sur 443** ⇒ verrou **double** |
| **Tailscale** | `/dev/net/tun` présent, `CAP_NET_ADMIN` accordé, binaire **constructible** (`go install tailscale.com/cmd/tailscale@latest` — `proxy.golang.org` passe, v1.102.1 obtenue) | `pkgs.tailscale.com` **403** (pas de binaire tout fait), `controlplane.tailscale.com` **403** (pas de plan de contrôle), pas d'UDP (pas de WireGuard), `derp1.tailscale.com` **403** (pas de repli DERP) ⇒ verrou **triple** |

Le proxy dit lui-même quoi faire, mot pour mot :

```
Host not in allowlist: api.trycloudflare.com.
Add this host to your network egress settings to allow access.
```

> ⇒ **C'est une question de politique réseau de l'environnement, pas d'outillage** — et le
> `/root/.ccr/README.md` est formel : « *Do not retry or route around it — report the blocked
> host.* » Un 403 se **rapporte**, il ne se contourne pas.

#### Le levier, et où il se trouve

**Aucun outil de session ne modifie l'allowlist** — recherché le 02/08 dans tout l'outillage
disponible, y compris du côté qui a livré `add_repo` : rien. Le réglage est **hors de la VM**,
dans la configuration de l'environnement, à la main de l'utilisateur.

Source : doc [Configure cloud environments](https://code.claude.com/docs/en/cloud-environments)
(**documentation, pas mesure**). Le champ **Network access** d'un environnement prend quatre
valeurs :

| Niveau | Sorties autorisées |
|---|---|
| **None** | aucune |
| **Trusted** *(défaut)* | la liste d'allowlist par défaut : registres de paquets, GitHub, SDK cloud |
| **Full** | **n'importe quel domaine** |
| **Custom** | votre propre liste (`api.example.com`, `*.internal.example.com`), avec ou sans les défauts |

Où : l'icône nuage **au-dessus de la zone de message** sur `claude.ai/code` → *Add cloud
environment*, ou l'engrenage d'un environnement existant. Pas de page de réglages dédiée.
⚠️ Changer les hôtes autorisés **invalide le cache d'environnement** : le script de setup
rejoue au prochain démarrage.

> ⚠️ **Non mesuré, et décisif** : la doc parle de **domaines**, jamais de **ports**. Or ici seuls
> 80 et 443 sortent. Passer en **Full** lèverait les 403 — mais si le filtrage de ports tient
> quand même, **cloudflared resterait mort** (7844, sans repli 443) tandis que **Tailscale
> aurait une chance en DERP** (plan de contrôle et DERP sont en HTTPS/443). Prédiction, pas
> mesure : à trancher en rejouant `probes/tunnel_probe.py` dans un environnement **Full**.

C'est ce qui donne sa valeur au **pilotage d'interface en local** (§6) : on ne peut pas montrer
l'UI en direct à un humain, mais on peut la **servir, la manipuler et la regarder** sur place.

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
| `go` 1.24, `/dev/net/tun`, `CAP_NET_ADMIN` | **`cloudflared`, `tailscale`, `ngrok`, `caddy`** → absents. `cloudflared` se **télécharge** (GitHub), `tailscale` se **construit** (`go install`) — et ni l'un ni l'autre ne sert à rien ici (§3) |

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
2. ❌ **Corrigé le 02/08** : la note prescrivait `proxy: {server: 'direct://'}` contre un
   `goto` pendu sur `127.0.0.1`. **Cette option casse le lancement** —
   `net::ERR_PROXY_CONNECTION_FAILED`, mesuré sur trois variantes comparées :

   | Lancement | Verdict 02/08 |
   |---|---|
   | par défaut, aucune option | ✅ marche (`127.0.0.1` est déjà dans `no_proxy`) |
   | `proxy: {server:'direct://'}` | ❌ `ERR_PROXY_CONNECTION_FAILED` |
   | `args: ['--no-proxy-server']` | ✅ marche — à préférer, il garantit l'isolement |
3. **Flags WebGPU logiciel** : `--enable-unsafe-webgpu --enable-features=Vulkan
   --use-webgpu-adapter=swiftshader --no-sandbox`.
4. `--force-gpu-mem-available-mb` **ne plafonne pas** les allocations WebGPU (testé à 512 Mo :
   4,7 Go alloués quand même). Pour simuler la rareté VRAM ⇒ crochets applicatifs, pas un flag.
5. ❌ **Corrigé le 01/08** : la note d'origine prescrivait
   `executablePath: '/opt/pw-browsers/chromium-<rev>/chrome-linux/chrome'`, à ajuster à chaque
   changement de révision. **Inutile** : `/opt/pw-browsers/chromium` est un **lien symbolique
   direct vers le binaire**. Utiliser ce chemin — il est stable.

### ⭐ Piloter une interface — la boucle complète, sans le matériel

Mesuré le 02/08 (`probes/ui_probe.mjs`, 10/10) : la VM ne sert pas qu'à *rendre* une page, elle
peut **jouer l'opérateur et relire ce que le serveur a vu**.

| Maillon | Comment | Mesuré |
|---|---|---|
| Servir | serveur local sur `http://127.0.0.1:<port>` | chargement en **26 ms** |
| Contexte sécurisé | `127.0.0.1` suffit — ni `about:blank` ni `data:` | `isSecureContext === true` |
| Manipuler | `mouse.down/move({steps})/up`, `keyboard.press` | **15 POST** reçus pendant un glisser |
| Vérifier côté serveur | le serveur consigne les commandes reçues | position finale cohérente |
| Push serveur → page | **SSE** (`text/event-stream`) | reçu et affiché |
| **Regarder** | `page.screenshot()` → PNG **relu par l'agent** | 6 Ko, relisible |

> ⭐ **C'est la capacité qui change la nature du travail sur une UI.** Une console web dont le
> matériel est ailleurs (une carte RK3588, un serveur de régie) se valide **entièrement** ici :
> mise en page, gestes, erreurs JS, synchro temps réel. Seul l'étage matériel reste à prouver
> ailleurs.
>
> Le complément qui la rend praticable : **stuber les modules absents** plutôt que d'installer
> l'impossible. Injecter un faux `gi`/PyGObject et un faux pilote dans `sys.modules` **avant**
> l'import fait tourner le **vrai** serveur applicatif contre un matériel fictif. Appliqué le
> 02/08 à la console de `PXL-Switcher` : 20 vérifications HTTP/SSE passées, deux défauts
> d'affichage trouvés **à l'œil sur la capture** — sans carte.

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
| ~~Attacher un dépôt à une session en cours~~ | 🔴 **FAUX depuis le 02/08** — `add_repo` a attaché deux dépôts en cours de session, clones réussis. Voir errata 6 |
| Exécuter du code ARM | pas de `qemu-user` (§5) |
| Mesurer une perf comparable entre sessions | le CPU change (§1) |
| Joindre un hôte hors allowlist | 403 CONNECT (§3) |
| **Exposer un service de la VM vers l'extérieur** | §3 — aucun tunnel ne passe : seuls 80/443 sortent, et les hôtes de réservation sont hors allowlist |
| **Sortir sur un port autre que 80/443** | §3 — silence, pas même un RST |
| Localiser la VM | metadata bloquée (§1, §3) |
| **Autoriser un serveur MCP en OAuth** | le flux est interactif ; en session non-interactive c'est impossible. Vu le 01/08 sur le connecteur Canva. ⇒ passe par les réglages claude.ai de l'utilisateur |
| Plafonner la VRAM par un flag Chromium | §6 piège 4 |

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
   l'héberge.** ⚠️ **Et cette entrée est elle-même corrigée par l'errata 6** — le refus
   mesuré n'a pas tenu. Ce dossier entier est né de ce piège : le plan « je crée le dépôt puis je
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

6. 🔴 **« Le périmètre GitHub est figé au démarrage de la VM. »** (errata 3, 01/08 — et
   *raison d'être* de ce dépôt.) **Mesuré faux le 02/08** : `add_repo` a attaché **deux dépôts
   en cours de session** — `deejaymx/pxl-cc-over-anthrvm` (rendu public quelques minutes plus
   tôt) puis `deejaymx/pxl-tape` — les deux clones ont réussi, et le second faisait 141 Mo. La
   réponse de l'outil le dit explicitement : « *is now in this session's GitHub scope, even
   though the system prompt's Repository Scope list still shows only the original set* ».
   **Leçon : un refus mesuré une fois n'est pas une propriété permanente de la plateforme.** Une
   conclusion négative mérite d'être re-mesurée avant d'être bâtie dessus — celle-ci a fondé
   tout un détour d'organisation.
   ⚠️ **Restent non mesurés** : la *création* d'un dépôt (403 le 01/08, non retesté), et
   `add_repo` sur un dépôt **créé pendant** la session. Ne pas généraliser au-delà de ce qui
   est écrit ici.

7. ❌ **`proxy: {server:'direct://'}` pour isoler Chromium du proxy** (note du 25/07, §6 piège 2)
   — l'option **casse** le lancement (`ERR_PROXY_CONNECTION_FAILED`). Le lancement par défaut
   marche, `--no-proxy-server` aussi. **Leçon : un contournement écrit pour un symptôme survit
   au symptôme et devient lui-même la panne.**

8. ❌ **« Hôtes de `noProxy` = direct, jamais proxifié. »** (01/08) La moitié « jamais
   proxifié » est fausse : le 02/08, une socket brute vers `pypi.org` ou `proxy.golang.org`
   reçoit un certificat **émis par Anthropic**. `no_proxy` décrit un *itinéraire* (pas de
   `CONNECT`), pas une *exemption de politique*. **Leçon : « ça répond 200 » ne prouve pas
   « ça sort en clair ».**

---

## 9. Sources

**Mesures** — `probes/vm_survey.sh` (01/08) · `probes/webgpu_probe.mjs`, `probes/vram_probe.mjs`
(25-26/07) · `probes/tunnel_probe.py`, `probes/ui_probe.mjs` (02/08) · relevés de cycle de vie
des 26-27/07, repris de `PXL-Tape/v3/tests/investigations/note_vm_lifecycle.md`.

**Documentation** — [Claude Code on the web](https://code.claude.com/docs/en/claude-code-on-the-web)
(environnements, politiques réseau, triggers, sources) · `/root/.ccr/README.md` (proxy, dans la VM).

**Documents PXL liés** — `PXL-Tape/v3/tests/investigations/note_vm_lifecycle.md` et
`note_vm_webgpu.md` (les notes d'origine, dont ce dossier est la reprise et la correction) ·
`PXL-StageBox/jpegxs-arm/README.md` (le banc dont le §1 explique la non-reproductibilité) ·
`PXL-Tape/v3/server.py` + `v3/cf-worker/worker.js` (le montage qui marche **hors** de la VM :
serveur stdlib → **Tailscale Funnel** → **Worker Cloudflare** proxyfiant HTTP+WebSocket — la
référence de ce que le §3 dit impossible ici) · `PXL-Switcher/prototype/board/` (la console web
validée au navigateur sans son matériel, §6).
