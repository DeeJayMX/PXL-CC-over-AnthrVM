# PXL CC-over-AnthrVM — la VM Claude Code, mesurée

> Ce que la machine **est**, ce qu'elle **sait faire**, et ce qu'elle **refuse**.
>
> Quatre campagnes : **25-27/07/2026** (WebGPU, cycle de vie), **01/08/2026** (GitHub, réseau,
> outillage) et **02/08/2026** (tunnels sortants, §3 bis). Tout ce qui suit est **mesuré depuis
> l'intérieur**, sondes à l'appui — sauf
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

## 3 bis. ⭐ Tunnels sortants — Tailscale passe, Cloudflare Tunnel non (mesuré le 02/08/2026)

Question posée : peut-on monter un tunnel depuis la VM (joindre une machine distante, exposer
un service de la VM) ? **Réponse mesurée : Tailscale oui, Cloudflare Tunnel non** — et la raison
n'est ni le client ni les privilèges, c'est **une seule ligne de politique réseau**.

### Les prérequis locaux sont tous réunis — et ne servent à rien

| | Mesuré 02/08 |
|---|---|
| uid | **0 (root)** |
| `CapEff` | `000001fffeffffff` — **toutes les capabilities**, `CAP_NET_ADMIN` compris |
| `/dev/net/tun` | **présent** (`crw------- 10, 200`) |
| `tailscale(d)` · `cloudflared` · `wg` · `ssh` préinstallés | **aucun** — mais tous téléchargeables (`pkgs.tailscale.com`, releases GitHub : HTTP 200) |

> ⚠️ **Ne pas s'arrêter là.** root + `/dev/net/tun` fait croire que tout est permis. Ces
> prérequis sont **nécessaires et pas suffisants** : ce qui décide est en amont, dans le filtre
> d'egress, et il ne se voit pas depuis `/proc`.

### ⭐ Le seul tableau qui décide : les ports ouverts en sortie

Testé en **dial direct** (hors `HTTPS_PROXY`), chaque cible connue ouverte sur son port pour
qu'un échec accuse le filtre et non l'hôte.

| Port | Verdict mesuré |
|---|---|
| **TCP 80**, **TCP 443** | ✅ **OUVERT** |
| **UDP 53** (vers `8.8.8.8`) | ✅ **OUVERT** — réponse en 3-6 ms |
| TCP 22 (SSH), TCP 853 (DoT) | ❌ `TimeoutError` (~6 s) |
| 🔴 **TCP 7844** (edge Cloudflare Tunnel) | ❌ `TimeoutError` |
| 🔴 **UDP 7844** (QUIC), **UDP 3478/19302** (STUN), **TCP 41641** (WireGuard) | ❌ aucune réponse |

> ⭐ **La règle, et elle explique tout le reste : l'egress se limite à TCP/80, TCP/443 et
> UDP/53.** Le filtrage est **par port, pas par protocole** — l'UDP n'est pas mort en bloc,
> UDP/53 répond (témoin explicite dans la sonde). Ce n'est **pas** le proxy de session : c'est
> une couche réseau *sous* lui, et **le proxy y est soumis lui aussi** (voir plus bas).

### Les deux clients, mesurés

| | Tailscale 1.98.10 | cloudflared 2026.7.3 |
|---|---|---|
| Téléchargement du binaire | ✅ | ✅ |
| Démarrage du démon | ✅ `--tun=userspace-networking` | ✅ |
| **Plan de contrôle** | ✅ `controlplane.tailscale.com:443` joint, **nœud enregistré, AuthURL délivrée** | ✅ tunnel créé, **hostname `*.trycloudflare.com` attribué** |
| **Plan de données** | ✅ **DERP en TCP/443** — les 26 relais répondent | 🔴 **échec** : `dial tcp …:7844: i/o timeout` en QUIC **et** en `--protocol http2` |
| Verdict | ✅ **passe**, en mode relayé | 🔴 **ne passe pas** |

`tailscale netcheck` (02/08) : `UDP: false` · `Nearest DERP: New York City` · latences DERP
**52,7 ms (nyc) → 271,9 ms (sin)**, les 26 régions joignables.

> ⭐ **Toute la différence tient au repli.** Les deux clients ont un plan de contrôle en 443 qui
> passe sans effort — c'est trompeur, cloudflared vous rend une URL publique avant d'échouer.
> Mais **Tailscale sait replier son plan de données sur TCP/443 (DERP)** quand l'UDP est mort,
> alors que **le plan de données de cloudflared est cloué sur le port 7844**, en QUIC comme en
> HTTP/2 — aucun repli 443 n'existe. Le hostname attribué répond **HTTP 530** : Cloudflare a la
> façade, jamais l'origine.
>
> ⇒ **Critère à appliquer à tout futur client de tunnel** : *sait-il parler par TCP/443 seul ?*
> Si oui il a une chance, sinon c'est mort — inutile de tester.

**Conséquences pratiques**, si on veut s'en servir :

1. Tailscale en session cloud fonctionne **en relais DERP uniquement** — jamais en pair-à-pair.
   Débit et latence sont ceux d'un relais TCP (≥ 52 ms d'aller simple sur le DERP le plus
   proche, ici NYC), **pas** ceux de WireGuard direct. Ne pas y faire passer de la vidéo.
2. L'auth interactive est hors d'atteinte (§7) ⇒ **`tailscale up --auth-key=tskey-…`**, seul
   chemin non interactif. La clé est un secret : la passer par l'environnement, **jamais dans un
   dépôt**.
3. `tailscaled` **honore `HTTPS_PROXY`** (traces `tshttpproxy: CONNECT response … 200` pour
   `controlplane` et `log.tailscale.com`). Il n'y a rien à configurer.
4. Pour exposer un service de la VM, Cloudflare Tunnel étant hors-jeu, il reste Tailscale
   Funnel — **non mesuré**, il exige un tailnet authentifié.

### ⚠️ Divergence avec le 01/08 : l'allowlist d'hôtes n'était pas là

Le 01/08, `mpv.io` et `api.ipify.org` rendaient `CONNECT tunnel failed, response 403` (§3). Le
**02/08, `mpv.io` est joignable**, et le proxy relaie sans broncher des hôtes arbitraires
(`pkgs.tailscale.com`, `region1.v2.argotunnel.com`, releases GitHub). `selective: false`,
`toolScoped: false` dans les deux relevés.

> ⚠️ **La politique réseau est un réglage d'ENVIRONNEMENT, pas une propriété de la VM.** Les
> deux mesures sont justes, à des dates et dans des environnements différents. Ce qui est stable
> d'un relevé à l'autre, ce n'est pas la liste d'hôtes — c'est **la restriction de ports**.
> ⇒ **Ne jamais conclure « le réseau est ouvert » d'un `curl` qui a marché** : relancer
> `probes/tunnel_probe.sh`.

### 🔴 Le piège : un `200 Connection Established` ne prouve rien

`CONNECT region1.v2.argotunnel.com:7844` à travers `$HTTPS_PROXY` répond **`HTTP/1.1 200
Connection Established`** — puis la connexion **pend et se fait reset à +6,2 s**, `time_appconnect`
restant à `0.000000` : le handshake TLS n'a **jamais** commencé. Le proxy émet son 200 **avant**
d'avoir joint la cible. Comparaison dans la même sonde : sur un hôte en 443, `time_appconnect`
vaut ~0,42 s — c'est **ce chiffre**, pas le code de retour, qui distingue un relais réel.

> ⚠️ **Et `recentRelayFailures` reste à `[]`.** Le champ d'introspection recommandé au §3
> **ne journalise pas ces échecs-là**. Première limite connue de l'outil de diagnostic : il dit
> qu'il n'a rien vu, pas qu'il n'y a rien eu. (Voir errata 6.)

*Indice de localisation, non concluant* : le profil de latences DERP place la VM près de la côte
est nord-américaine (nyc 52,7 ms < iad 56,2 < ord 60 ≪ par 129,1). Mais **52 ms jusqu'à NYC est
trop élevé** pour une VM *dans* cette région, et l'ordre nyc < iad ne cadre pas avec l'hypothèse
AWS `us-east-1` du §1 — les sondes DERP incluent des handshakes complets, donc plusieurs RTT.
**À ne pas convertir en conclusion** : c'est exactement le genre d'inférence que l'errata 1
punit. Le §1 reste « localisation indéterminable ».

---

## 3 ter. La clé Tailscale — ce qui peut survivre à un recyclage, et ce qui ne le peut pas
*(établi le 03/08/2026, à la demande d'Eliott : « garder persistante la clef Tailscale »)*

Le tunnel remonte à chaque VM neuve, et à chaque fois il faut ré-authentifier. La question
posée est donc : où poser la clé pour ne plus jamais le refaire à la main ?

**🔴 La clé de NŒUD ne peut pas être rendue persistante.** Deux murs, et aucun des deux ne se
contourne par du code :

1. Le `statedir` de tailscaled vit dans le workdir. Le §2 dit ce qu'il advient du workdir : au
   réveil suivant, il a disparu avec la VM.
2. Le versionner serait **pire que le perdre**. `tailscaled.state` contient la clé privée du
   nœud ; la pousser sur GitHub, c'est publier de quoi se faire passer pour cette machine sur
   le tailnet. Un dépôt n'est pas un coffre, et celui-ci est écrit pour être lu.

**⭐ Ce qui peut être persistant, c'est la clé d'AUTHENTIFICATION**, et il n'existe qu'un seul
endroit du dispositif qui survive à un recyclage sans être un dépôt git : les **variables
d'environnement de l'environnement Claude Code**, réappliquées à chaque démarrage de session.
La VM redevient neuve, la clé la réattend.

| | |
|---|---|
| Où | réglages de l'environnement → variables d'environnement → `TS_AUTHKEY` |
| Quoi | une auth key **réutilisable** (Tailscale admin → Settings → Keys → Reusable) |
| ⚠️ Durée | **90 jours au maximum**, plafond Tailscale. Ça ne se contourne pas : il faudra la régénérer |

`tunnel_up.sh` à la racine consomme cette variable et remonte tout : téléchargement des
binaires (absents d'une VM neuve, retirés par TCP/443), démon en `--statedir`, `up --auth-key`,
puis `serve`. Idempotent — il ne relance pas ce qui tourne. La clé ne transite que par
l'environnement du processus : jamais affichée, jamais écrite, **jamais en argument de ligne de
commande**, `ps` étant lisible par tout le monde.

⚠️ **`serve`, jamais `funnel`.** `serve` publie sur le tailnet seul ; `funnel` ouvre sur
l'internet public. L'exposition publique a été coupée sur décision d'Eliott le 02/08/2026, et un
réarmement automatique la rouvrirait par effet de bord d'un redémarrage. Si Funnel revient un
jour, que ce soit une ligne écrite exprès.

**Mesuré le 03/08** : sans `TS_AUTHKEY`, le script refuse immédiatement avec la marche à suivre
(code 1) ; avec une clé factice, il télécharge les binaires, démarre le démon et échoue
**à l'authentification** avec le diagnostic « clé expirée ou à usage unique ». Les trois étapes
sont donc exercées. ⚠️ Ce qui n'est **pas** mesuré, faute de clé réelle dans cette session :
qu'une vraie clé réutilisable ré-authentifie effectivement une VM neuve. Le mécanisme
`--auth-key` est lui mesuré au §3 bis (02/08) ; c'est sa reconduction automatique d'une session
à l'autre qui reste à confirmer au premier réveil.

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

### 4 bis. `add_repo` fonctionne — **mesuré le 02/08/2026** ⭐

Le 🔴 ci-dessus tenait sur un rapport de l'extérieur et le disait : *« non vérifié de
l'intérieur, `add_repo` n'ayant pas été appelé »*. Il a été appelé le 02/08, en cours de
session, sur deux dépôts hors périmètre de démarrage. **Les deux ont été attachés puis clonés.**

| Étape | Résultat |
|---|---|
| `add_repo {owner: DeeJayMX, repo: pxl-airlink, access: read}` | ✅ `status: appended`, périmètre porté à 3 dépôts |
| `add_repo` sur `PXL-SPOUT-TurboHQ` | ✅ périmètre porté à 4 |
| `git clone --depth 1` des deux | ✅ dans `/workspace/<repo>` |
| `list_repos` (13 dépôts rendus) | ✅ — il voit **au-delà** du périmètre de session |

Trois choses apprises, et la troisième est la vraie leçon :

1. **Le périmètre n'est pas figé au démarrage.** Il l'est *par défaut* ; `add_repo` l'étend.
   L'invite système continue d'afficher la liste du démarrage — la réponse de l'outil le dit
   explicitement : *« now in this session's GitHub scope, even though the system prompt's
   Repository Scope list still shows only the original set »*. **La liste affichée n'est donc
   pas la liste effective**, et c'est exactement ce qui pouvait faire renoncer sans essayer.
2. **`list_repos` est le bon réflexe avant de déclarer un dépôt inatteignable** : il énumère ce
   que le compte peut attacher, pas ce qui est déjà attaché.
3. ⚠️ **Le verrou qui reste est celui de la *création*.** Rien ici ne contredit le 🔴 sur
   `POST /user/repos` : attacher un dépôt **qui existe** et en *créer* un sont deux opérations
   différentes. La « conséquence, et c'est le piège » ci-dessus perd en revanche une de ses deux
   moitiés — un dépôt créé à la main pendant la session est désormais attachable **sans
   attendre la session suivante**. La séquence « partir de rien » reste bloquée, mais seulement
   par la création.

> ⚠️ **Ce que ça ne prouve pas** : que ça marche pour tout dépôt. Les quatre attachés
> appartiennent au compte d'Eliott, et la réponse de l'outil décrit des refus possibles —
> dépôt non activé pour l'organisation, App GitHub non installée — qui demandent une action
> d'admin. Mesuré : les dépôts personnels du propriétaire de la session. Non mesuré : un dépôt
> d'organisation tierce.

> **Note d'exploitation** : l'outil impose **un clone à la fois** (2 opérations smart-HTTP
> concurrentes maximum par dépôt, sinon HTTP 429 qui fait échouer *les deux*), et un délai
> généreux — un pack volumineux peut prendre 5 à 10 min, `index-pack` a l'air pendu sans l'être.

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

   > ⚠️ **Divergence mesurée le 02/08** (Chromium 141.0.7390.37 + `playwright-core` 1.62.1) :
   > **`proxy: {server: 'direct://'}` ne marche plus** — `net::ERR_PROXY_CONNECTION_FAILED`.
   > `proxy: {server:…, bypass:'<-loopback>'}` échoue pareil. **Seul `args: ['--no-proxy-server']`
   > joint le loopback** (le `ERR_INVALID_AUTH_CREDENTIALS` obtenu au banc d'essai est un 401
   > applicatif : la connexion, elle, a abouti). Les deux recettes du 25/07 étaient données comme
   > équivalentes ; elles ne le sont plus. **⇒ Utiliser `--no-proxy-server`.**
3. **Flags WebGPU logiciel** : `--enable-unsafe-webgpu --enable-features=Vulkan
   --use-webgpu-adapter=swiftshader --no-sandbox`.
4. `--force-gpu-mem-available-mb` **ne plafonne pas** les allocations WebGPU (testé à 512 Mo :
   4,7 Go alloués quand même). Pour simuler la rareté VRAM ⇒ crochets applicatifs, pas un flag.
5. ❌ **Corrigé le 01/08** : la note d'origine prescrivait
   `executablePath: '/opt/pw-browsers/chromium-<rev>/chrome-linux/chrome'`, à ajuster à chaque
   changement de révision. **Inutile** : `/opt/pw-browsers/chromium` est un **lien symbolique
   direct vers le binaire**. Utiliser ce chemin — il est stable.

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
| ~~**Attacher un dépôt à une session en cours**~~ **← INFIRMÉ le 02/08** | ~~§4 — le périmètre est figé au démarrage~~ · `add_repo` marche : **§4 bis**, errata 7. Ligne barrée et non retirée — elle a orienté une session entière, la voir barrée vaut mieux que ne plus la voir |
| Exécuter du code ARM | pas de `qemu-user` (§5) |
| Mesurer une perf comparable entre sessions | le CPU change (§1) |
| Joindre un hôte hors allowlist | 403 CONNECT (§3) |
| Localiser la VM | metadata bloquée (§1, §3) |
| **Autoriser un serveur MCP en OAuth** | le flux est interactif ; en session non-interactive c'est impossible. Vu le 01/08 sur le connecteur Canva. ⇒ passe par les réglages claude.ai de l'utilisateur |
| Plafonner la VRAM par un flag Chromium | §6 piège 4 |

> ⚠️ **Ce qui n'a pas sa place dans ce tableau : les tunnels sortants.** Cloudflare Tunnel
> échoue (§3 bis) et Tailscale ne passe qu'en relais DERP — mais **parce que l'egress est
> restreint à TCP/80, TCP/443 et UDP/53**, et cette restriction est un réglage
> d'**environnement**, pas une propriété de la VM (elle a déjà divergé entre le 01/08 et le
> 02/08). Ce n'est donc pas « définitif » : c'est à **re-mesurer** par
> `probes/tunnel_probe.sh` au début de chaque session qui en dépend.

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

6. ❌ **« Le proxy de session, lui, relaie le port 7844 — il échappe au filtre. »** (02/08,
   conclu à chaud d'un `HTTP/1.1 200 Connection Established` sur `CONNECT …:7844`) Faux : le 200
   est **optimiste**, émis avant que la cible soit jointe ; la connexion pendait et se faisait
   reset 6,2 s plus tard, `time_appconnect` à zéro. **Leçon : un code de retour d'établissement
   ne mesure pas l'établissement — c'est le temps de handshake TLS qui tranche.** Aggravant :
   `recentRelayFailures` est resté vide, donc **l'outil de diagnostic du §3 confirmait
   l'illusion par son silence**. Un champ vide n'est pas un constat d'absence d'échec. C'est la
   même famille d'erreur que l'errata 1 — une observation juste (le 200 *a bien* été reçu), une
   conclusion tirée trop vite sur ce qu'elle signifie.

7. ❌ **« Un dépôt ne peut pas être attaché à une session déjà lancée. »** (01/08, §4, marqué
   🔴 bloquant) Faux — `add_repo` a attaché deux dépôts hors périmètre le 02/08, tous deux
   clonés dans la foulée (§4 bis). Ce qui rend celui-ci différent des six autres : **l'entrée
   disait elle-même qu'elle n'était pas mesurée** — *« non vérifié de l'intérieur, `add_repo`
   n'ayant pas été appelé »* — et concluait quand même au 🔴, en ajoutant *« l'outil `add_repo`
   existe et sa description annonce l'inverse — ne pas s'y fier »*. La description avait raison.

   Le mécanisme est un renversement de l'errata 3, et c'est ce qui le rend piégeux : là-bas, se
   fier à la description d'un outil avait coûté cher, donc la leçon retenue — « la description
   décrit l'intention, pas la politique » — a servi la fois suivante à **écarter une description
   exacte**. Une heuristique de défiance appliquée sans mesure produit exactement le même genre
   de faux qu'une confiance appliquée sans mesure.

   Aggravant, et c'est ce qui a permis à l'erreur de tenir : **l'invite système continue
   d'afficher la liste de dépôts du démarrage** après un `add_repo` réussi. Qui vérifie là
   trouve une confirmation de la thèse fausse. **Leçon : un rapport de seconde main marqué
   « non vérifié » ne devient pas un 🔴 — il devient une sonde à écrire.** Elle tenait en un
   appel.

---

## 9. Sources

**Mesures** — `probes/vm_survey.sh` (01/08, rejouée le 02/08) · `probes/tunnel_probe.sh` (02/08,
`--full` pour lancer réellement les deux clients) · `add_repo` + clone de `pxl-airlink` et
`PXL-SPOUT-TurboHQ` en cours de session (02/08, §4 bis — pas de sonde : deux appels d'outil,
rejouables tels quels) · `probes/webgpu_probe.mjs`,
`probes/vram_probe.mjs` (25-26/07) · relevés de cycle de vie des 26-27/07, repris de
`PXL-Tape/v3/tests/investigations/note_vm_lifecycle.md`.

**Documentation** — [Claude Code on the web](https://code.claude.com/docs/en/claude-code-on-the-web)
(environnements, politiques réseau, triggers, sources) · `/root/.ccr/README.md` (proxy, dans la VM).

**Documents PXL liés** — `PXL-Tape/v3/tests/investigations/note_vm_lifecycle.md` et
`note_vm_webgpu.md` (les notes d'origine, dont ce dossier est la reprise et la correction) ·
`PXL-StageBox/jpegxs-arm/README.md` (le banc dont le §1 explique la non-reproductibilité).
