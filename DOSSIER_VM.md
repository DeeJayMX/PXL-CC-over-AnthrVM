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
6. **Nuit ou absence longue** (20/08) : armer les réveils **avant** — une Routine de garde
   auto-réarmante (~45 min) par session, plus, chez un orchestrateur, **un trigger de réveil
   par session pilotée** (voir la nuit du 19-20/08 ci-dessous : c'est le seul mécanisme qui a
   ressuscité le banc). Accepter d'avance la perte de tout état en mémoire.

### 🌙 La nuit du 19-20/08 — l'endurance multi-VM, mesurée en vraie grandeur

Le banc : trois VM (une tour d'orchestration + deux labos), des flux vidéo permanents en
duplex croisé sur le tailnet, mission « rien ne s'arrête jusqu'au matin ». Résultat brut :
**les trois conteneurs sont morts dans la première heure** (labo A ~23:45Z, labo B ~00:20Z,
la tour coupée en plein tour vers 23:46Z) et rien n'a tourné jusqu'au réveil manuel à 06:10Z.
Dernier commit de la nuit : 23:48Z. Ce que la nuit enseigne, dans l'ordre des dégâts :

- **Les nœuds tailscale éphémères meurent DEUX fois.** Un nœud hors ligne est *supprimé* du
  tailnet (clé éphémère) — et une longue absence **expire l'enregistrement** : au retour, le
  nœud est *logged out* et la configuration `tailscale serve` est **effacée**. Le remontage
  n'est donc jamais « relancer tailscaled » : c'est `tailscale up --authkey` complet + re-`serve`.
  Procédure scriptée dans `PXL-TurboHQ` (branche transport-lab, `lab/remount_a.sh`).
  L'état local (`tailscaled.state`) survivant dans le workdir redonne la **même IP** — seuls
  l'enregistrement côté plan de contrôle et le serve expirent.
- **Une tâche suivie par le harnais ne maintient PAS le conteneur en vie une nuit.** La tour
  avait un Monitor persistant actif : son conteneur a redémarré quand même. La règle 2 protège
  la *sémantique* (notification, reprise) — pas la machine. L'ancienne note « `run_in_background`
  = VM maintenue ≥ 1 h » est un ordre de grandeur, pas un contrat, et ne s'étend pas à 6 h.
- **Un tour peut enjamber un redémarrage — avec des heures au milieu.** Le tour de 23:46Z de la
  tour a été coupé après son premier appel d'outil (parti à 23:46) ; à la reprise de session,
  les appels restants ont exécuté à **06:10Z**. Les actions d'un même tour ne sont pas
  simultanées : écrire les enchaînements critiques de façon idempotente, et dater ce qu'on
  envoie (un « ordre de nuit » livré au matin sème la confusion).
- **Les tours déclenchés par trigger n'ont pas les outils MCP** (confirmé en vraie grandeur) :
  une session réveillée par Routine ne peut pas armer son propre `send_later` dans ce tour-là.
  Parade des labos : garde-fou en tâche harnais (une mort du process réveille la session) et
  `send_later` armé depuis un tour *interactif*. Piège supplémentaire vu au matin : une demande
  d'**approbation MCP** en attente bloque silencieusement le `send_later` d'une session — le
  garde-fou qu'on croit armé ne l'est pas.
- **Ce qui a marché** : la chaîne de résurrection côté serveur. Le watchdog mutuel des labos a
  daté les chutes ; la tour tenait **un trigger de réveil pré-créé par session** (créés avant la
  nuit, prompt de remontage complet) ; deux `fire_trigger` au matin ont tout relevé en ~15 min,
  y compris après un second recyclage du labo A à ~06:15Z. Et le workdir a tenu sa promesse :
  binaires Go, clones, `tailscaled.state` et sondes `.idx` de la nuit étaient encore là — le
  post-mortem est possible parce que les sondes écrivaient **sur disque**, pas en mémoire.

### ⏰ L'horloge de la VM — livrée à elle-même (sondé le 20/08, 3 VM)

**La wall-clock d'une VM n'est disciplinée par rien.** Sondes concordantes sur trois VM du
même environnement :

- **Dans la VM** : aucun démon de temps (ni chronyd, ni ntpd, ni systemd-timesyncd — pas de
  systemd tout court), pas de `/dev/ptp*`, pas de chargement de module possible (`modprobe`
  absent) donc pas de `ptp_kvm` pour lire l'horloge de l'hyperviseur. Clocksource `tsc`
  (`kvm-clock` disponible mais non utilisé). L'horloge est posée au boot puis **dérive seule**
  — et vite : **~125 ppm mesurés** sur l'une des trois VM (≈ 11 s/jour), par suivi d'offset
  min-RTT sur 40 min.
- **Vers l'extérieur** : aucune heure vraie atteignable — NTP public (UDP 123) bloqué par
  l'egress, NTS (TCP 4460) bloqué, et l'en-tête `Date` HTTPS à travers le proxy vaut entre
  ±150 ms et ±0,5 s avec des sources qui se **contredisent** (google et github : intervalles
  disjoints — granularité 1 s + latence proxy asymétrique).
- **Conséquence mesurée** : étalement de **~0,3 s entre trois VM** du même environnement
  (offsets muraux mesurés min-RTT : +74,5 ms entre les deux labos, −277 ms tour↔labo, miroirs
  vérifiés à 1 ms près dans les deux sens). Toute comparaison de timestamps muraux entre VM
  est donc **fausse de dizaines à centaines de ms** — les latences aller simple inter-VM
  n'ont aucun sens sans correction (on a mesuré des latences *négatives*).
- **La parade** : une synchro applicative maître/mesh (offset NTP-lite min-RTT sur
  `/api/time`, ±0,5 ms en local, ±rtt/2 en relayé) — spec `CLOCK.md` et classement complet
  des sources d'heure dans `PXL-TurboHQ/pxl-turbohq-client/` (`CLOCK_SOURCES.md`). Les
  mesures aller-retour (RTT/2), elles, restent justes sans rien : une seule horloge mesure.

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

> 🔴🔴 **ERRATUM MAJEUR (19/08) : la règle « par port » du §3 bis (02/08) est OBSOLÈTE — la
> couche d'egress est devenue une passerelle TLS interceptante à liste d'hôtes.** Mesuré dans le
> MÊME environnement que le 03/08 :
>
> - en dial **direct** (hors `HTTPS_PROXY`), `controlplane.tailscale.com:443` connecte en 4 ms
>   (impossible pour la vraie côte Est — c'est un intercepteur local) et rend **HTTP 403** avec
>   un certificat émis par **`O=Anthropic, CN=Egress Gateway SDS Issuing CA (production)`** ;
> - le corps du 403 dit tout : *« Host not in allowlist: controlplane.tailscale.com. **Add this
>   host to your network egress settings** to allow access. »* ;
> - témoins : `pypi.org` direct → 200 ; `example.com` direct → 403. **Filtrage par HÔTE, plus
>   par port.** Les relais DERP (`derp*.tailscale.com:443`) sont 403 au même titre — le repli
>   DERP-sur-443 du §3 bis ne contourne plus rien, la couche du dessous lit désormais le SNI.
>
> ⇒ Le remède n'est PAS du code : ajouter `*.tailscale.com` (au minimum `controlplane.` +
> `derp*.` + `log.`) dans **Network egress settings** de l'environnement (claude.ai/code →
> nuage → roue dentée). Le proxy de session, lui, refuse aussi (`connect_rejected … policy
> denial` dans `recentRelayFailures`) — les deux étages obéissent au même réglage.
>
> Contournement partiel toujours valable : quand seul le TÉLÉCHARGEMENT est bloqué
> (`pkgs.tailscale.com`), `go install tailscale.com/cmd/tailscale{,d}@v1.98.10` compile les
> binaires en ~3 min via `proxy.golang.org` (dans la `noProxy`, donc toujours ouvert — Go
> 1.24.7 préinstallé). Mais tant que `controlplane.tailscale.com` est refusé, le nœud ne
> s'authentifiera jamais : inutile d'insister côté code.

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

#### ⭐ Marche à suivre — ce qui est automatique, et ce qui reste à faire une fois

**Automatique.** Un hook `SessionStart` (`.claude/settings.json` → `session_start.sh`) relance à
chaque invocation, dans cet ordre : la **console**, puis le **tunnel**. Idempotent — sur une
session déjà chaude il ne relance rien et rend la main en ~10 s. Il détecte aussi le cas du
proxy qui a changé de port (voir plus bas) et relance `tailscaled` quand c'est arrivé. Il sort
**toujours en 0** : un hook qui échoue ferait échouer le démarrage de la session.

**À faire UNE fois**, dans les variables d'environnement de l'environnement Claude Code
(claude.ai/code → icône nuage au-dessus de la saisie → roue dentée) :

| Variable | Pourquoi |
|---|---|
| `TS_AUTHKEY` | sans elle, pas de tunnel. Clé **réutilisable + éphémère + taguée** |
| `PXL_CONSOLE_MOTDEPASSE` | sans elle, le serveur en **tire un au sort à chaque réveil** et la console devient inutilisable en pratique |

⚠️ Les deux sont lisibles par quiconque utilise l'environnement — ce n'est pas un coffre, voir
plus bas. Un mot de passe de console derrière un tailnet et une ACL est un risque proportionné ;
la clé Tailscale, elle, doit être scopée (éphémère + taguée) plutôt que crue cachée.

**À faire à la main quand ça casse** : rien, en principe. Si le hook n'a pas tourné,
`bash session_start.sh` fait la même chose.

#### Où se règlent les variables d'environnement — ce n'est pas dans les réglages

⭐ **Il n'y a ni page de réglages ni URL directe** pour ça, et c'est pour cette raison qu'on peut
le chercher longtemps. La doc le dit : « *There's no settings page or direct URL for the
selector.* » Le chemin réel :

1. **claude.ai/code**
2. dans la rangée **au-dessus de la zone de saisie**, l'**icône nuage portant le nom de
   l'environnement courant** (« Default » par défaut)
3. **Add cloud environment**, ou survoler un environnement existant → **roue dentée** à droite
4. la boîte contient Name · Network access · **Environment variables** · Setup script
5. format `.env`, une paire `CLÉ=valeur` par ligne

⚠️ **Les valeurs sont copiées au DÉMARRAGE de la session.** Modifier une variable n'atteint que
les sessions ouvertes ensuite ; celles qui tournent gardent ce avec quoi elles ont démarré.

#### 🔴 Mais ce n'est PAS un coffre à secrets, et la doc l'interdit explicitement

> *Anyone who uses the environment can read the values, and cloud environments have **no
> dedicated secrets store**, so **don't add API keys or other credentials**.*

La boîte de dialogue affiche cet avertissement elle-même. Il n'existe **aucun** endroit sûr dans
ce dispositif : ni les variables d'environnement, ni le setup script (même visibilité), ni le
dépôt (public par nature). Le tableau « what carries over » range d'ailleurs *Static API tokens
and credentials* en **No**, avec « No dedicated secrets store exists yet ».

⚠️ Aggravant sur un compte **Pro/Max** : une session partagée est **publique**. Une clé tapée à
la main dans une session, ou affichée par une commande, part avec le partage.

**La bonne question n'est donc pas « où la cacher » mais « comment rendre sa fuite sans
conséquence ».** Une auth key Tailscale, contrairement à un token d'API, se **scope** :

| Option à la génération | Ce qu'elle achète |
|---|---|
| **Reusable** | sans elle la clé ne sert qu'une session — le problème n'est pas résolu |
| **Ephemeral** | le nœud se supprime seul dès qu'il se déconnecte : un recyclage ne laisse pas de fantôme, et une clé volée ne donne qu'un nœud qui s'évapore |
| **Tag** (`tag:pxl-vm`) + ACL | le nœud ne peut qu'atteindre ce que l'ACL autorise, et rien du reste du tailnet |
| Expiration courte (30 j) | réduit la fenêtre ; ⚠️ **90 jours est le plafond Tailscale**, ça ne se contourne pas |

Ainsi scopée, le pire cas d'une fuite devient « un nœud éphémère, tagué, borné par ACL », et non
« quelqu'un est sur le réseau ». C'est un risque **acceptable en connaissance de cause** — ce qui
est la seule forme acceptable ici, puisque aucune option ne le supprime.

| | |
|---|---|
| Où | claude.ai/code → icône nuage au-dessus de la saisie → roue dentée → Environment variables |
| Quoi | `TS_AUTHKEY=tskey-auth-…`, clé **réutilisable + éphémère + taguée** |
| 🔴 Visibilité | lisible par quiconque utilise l'environnement — ce n'est pas un coffre |

`tunnel_up.sh` à la racine consomme cette variable — d'où qu'elle vienne — et remonte tout : téléchargement des
binaires (absents d'une VM neuve, retirés par TCP/443), démon en `--statedir`, `up --auth-key`,
puis `serve`. Idempotent — il ne relance pas ce qui tourne. La clé n'est jamais affichée ni
écrite sur le disque.

⚠️ **Mesuré le 03/08 (Tailscale 1.98.10, `up --help`)** : `tailscale up` **ne lit pas**
`TS_AUTHKEY` dans son environnement — `--auth-key` est la seule entrée, et sa seule alternative
`--auth-key=file:/chemin` l'écrit sur le disque, ce qui est pire. La clé apparaît donc dans
`/proc/<pid>/cmdline` le temps de l'appel. Mesuré aussi : la VM tourne en **uid 0** et
`/proc/self/environ` est en **0400** — un seul utilisateur, donc la même frontière de confiance
que l'environnement lui-même. C'est acceptable *ici* et 🔴 pas sur une machine partagée.

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

### ⭐ Mise en service, mesurée le 03/08/2026 au matin

Première remontée réelle du tunnel avec une clé posée dans l'environnement. Ce qui a été
observé, dans l'ordre, et ce qu'il faut en conclure — ou pas.

**1. La variable n'arrive PAS « en direct ».** L'hypothèse était plausible (la valeur était là
après un simple rafraîchissement) et elle est fausse. Mesuré au moment où `TS_AUTHKEY` est
apparu : `uptime` = **55 s**, `CCR_SPAWN_TIMESTAMP_MS` = 50 s plus tôt. Rafraîchir a
**re-provisionné une VM neuve**, qui a lu la configuration à *son* démarrage — ce que dit la
doc. Le résultat est bon, le mécanisme n'est pas celui qu'on croit : ce n'est pas une synchro,
c'est une renaissance. ⇒ **Pour qu'une variable prenne effet : la poser, puis provoquer une
session neuve.**

**2. Le conteneur PERSISTE entre les invocations.** Seconde hypothèse à écarter (« ça se refresh
à chaque appel ») : `uptime` mesuré deux fois à 30 s d'intervalle donne **55 s puis 86 s**, et
`ps -o lstart= -p 1` rend la même heure de démarrage. Une seule naissance, au rafraîchissement.

**3. Workdir survivant sur VM neuve** — le canari du 02/08 17:18 est retrouvé alors que la VM
date de 09:47 le lendemain. Reconfirme l'errata 1 : le clone n'est pas refait à chaque VM.

**4. ⭐ Le tag fonctionne.** `tailscale status --json` rend `Self.Tags = ["tag:pxl-vm"]`. La
policy avait été enregistrée AVANT la génération de la clé, ce qui est l'ordre obligatoire : un
tag non déclaré dans `tagOwners` n'est pas proposé au moment de créer la clé.

**5. ⚠️ Le nœud s'appelle `pxl-console-1`, pas `pxl-console`.** Un nœud homonyme de la veille,
créé **avant** le passage à l'éphémère, occupait encore le nom — hors ligne mais présent. ⇒
**L'éphémère ne rattrape pas le passé** : il ne s'applique qu'aux nœuds nés d'une clé éphémère.
Les anciens se suppriment à la main dans la console d'admin, sinon les suffixes s'accumulent.

Question posée sur le coup : peut-on le récupérer ? **Techniquement oui** — le scratchpad a
survécu, `ts.state` (2799 o) et `ts-var/` y sont encore, il suffirait d'y repointer `tailscaled`.
🔴 **Mais il ne faut pas** : `status --json` le montre **sans aucun tag**, puisqu'il date d'avant
la policy. Le ressusciter remettrait sur le tailnet un nœud qui agit *en tant que l'utilisateur*,
avec tous ses droits — exactement ce que le tag venait d'éliminer. **Récupérable n'est pas
souhaitable.** Et tant qu'il existe côté Tailscale, sa clé qui traîne dans `/tmp` reste un
identifiant valide pour une machine non taguée : le supprimer dans la console rend le fichier
inerte, et libère le nom pour la VM suivante.

**Suite, même matinée** : le fantôme a été supprimé par Eliott, et le nom repris — voir la
mesure 7, qui est ce que cette reprise a appris.

**6. 🔴 L'ACL ne peut PAS être vérifiée depuis la VM, et un échec ici ne prouve rien.**
`curl https://pxl-console-1.<tailnet>.ts.net/` rend `000` — tentant à lire comme « l'isolation
marche ». C'est faux, et la mesure le montre :

| Chemin | Résultat | Ce que ça dit |
|---|---|---|
| via le proxy de session | `CONNECT tunnel failed, response 502` | le proxy ne joint pas un nom non public |
| `--noproxy '*'` | `Could not resolve host` | MagicDNS n'est pas configuré (`--accept-dns=false`) |
| `http://127.0.0.1:8710/` | **200** | la console tourne bien |

Aucune des deux erreurs n'est un refus d'ACL. **Seul un poste du tailnet peut vérifier la règle
`autogroup:member → tag:pxl-vm:443`.** C'est exactement le piège de l'errata 1 et du §3 bis : une
opération identifiée par son symptôme n'est pas identifiée pour autant.

**7. ⚠️ DEUX noms, deux durées de vie — et c'est le mauvais qu'on regarde.** Un nœud Tailscale
porte un `HostName` (le nom affiché dans la liste des machines) et un `DNSName` (le FQDN
MagicDNS, celui qu'on tape dans le navigateur). **Ils ne bougent pas ensemble.**

Déroulé mesuré le 03/08 :

| Étape | `HostName` | `DNSName` |
|---|---|---|
| nœud homonyme encore présent | `pxl-console-1` | `pxl-console-1.<tailnet>.ts.net` |
| l'homonyme est supprimé | **`pxl-console`** ← revient seul | `pxl-console-1.…` ← **ne bouge pas** |
| après `logout` + `up` | `pxl-console` | **`pxl-console.…`** |

Le suffixe `-1` est un marqueur de collision. Supprimer le nœud qui occupait le nom libère le
`HostName`, et Tailscale le rend spontanément à celui qui le demandait — **mais le `DNSName` est
figé à l'ENREGISTREMENT.** On voit donc le bon nom dans la console d'admin pendant que l'URL
continue de porter le suffixe, et on cherche pourquoi « ça ne marche pas ». C'est le genre de
divergence qu'on met dix minutes à voir parce que les deux champs se ressemblent.

⭐ **La reprise ne demande PAS de recréer la VM.** Le nœud étant éphémère, `tailscale logout` le
retire du tailnet et `tailscale up` le ré-enregistre sur le nom devenu libre — sans toucher au
conteneur, donc sans perdre la console qui tourne ni les processus. Un rafraîchissement de
session aurait coûté tout ça pour le même résultat (voir mesure 1 : rafraîchir = VM neuve).
⚠️ `serve` est réattaché au nouveau nom par le même passage de `tunnel_up.sh`, mais il faut que
la console écoute AVANT, sinon on publie un port mort.

**8. ⚠️ Le nœud éphémère ne survit pas à la session.** C'est le prix, assumé, du nettoyage
automatique : à chaque VM neuve il faut relancer la console puis `bash tunnel_up.sh 8710`. Ce qui
persiste d'une session à l'autre, c'est `TS_AUTHKEY` et rien d'autre.

**9. Bug du script, corrigé.** La ligne finale sortait vide : le nom était extrait par
`grep -o '"DNSName":"[^"]*"' | head -1`, qui attrape le premier `DNSName` du JSON et pas celui de
`Self`. Lire une structure avec un outil qui ne la comprend pas marche jusqu'au jour où l'ordre
des clés change. Il lit maintenant `.Self` avec un parseur JSON, et affiche le tag avec.

### 🔴 Mesuré le 03/08 — pourquoi l'entrant ne passait pas, et ce que ce n'était PAS

Une matinée entière, et la cause n'était aucune de celles qu'on soupçonnait. Elle mérite d'être
écrite avec les fausses pistes, parce que ce sont elles qu'on refera.

**Le symptôme, et sa forme trompeuse.** Depuis un poste du tailnet : `tailscale ping` en timeout,
SYN TCP jamais posé, HTTPS injoignable. Depuis la VM : tout marche. On peut pinguer les pairs et
recevoir 120 pongs sur 120. **Disco bidirectionnel, TCP entrant nul.** Cette asymétrie ressemble
à un pare-feu, à une ACL, à un certificat — à tout sauf à sa cause.

**⭐ La cause : le RELAIS HOME.** La VM est hébergée aux États-Unis. Son `netcheck` ne sonde que
des régions américaines (nyc 52 ms, iad, ord, den, mia, tor, dfw, sfo — aucune européenne) et
elle choisit `nyc` comme relais home. Les pairs qui veulent la joindre **sans sollicitation**
envoient vers ce relais. Rien n'arrive. Le sens sortant marche parce que c'est *nous* qui ouvrons
une connexion vers la région du pair (`par`), et les réponses reviennent dessus.

Correction mesurée : `tailscale debug force-prefer-derp <région du pair>` puis
`break-derp-conns`. Avec home = `par`, **tout passe, ACL stricte inchangée, sans aucun
keepalive**. ⚠️ `force-prefer-derp` est « until restart » — il est donc réappliqué à chaque
passage de `tunnel_up.sh`, qui détecte tout seul la région la plus peuplée chez les pairs en
ligne (surchargeable par `TS_DERP_REGION`).

**❌ Ce que ce n'était PAS, et qui a coûté le plus de temps : l'ACL.** Elle a été soupçonnée deux
fois et innocentée deux fois, la seconde de façon décisive :

* pendant la panne, `tailscale debug netmap` montrait déjà la règle
  `pxl-aero → 100.86.90.119:443` **présente et correcte** — le filtre autorisait, et ça ne
  passait pas quand même ;
* après correction du relais, la **policy stricte remise en place**, tout fonctionne.

⚠️ Entre les deux, une coïncidence a failli faire conclure l'inverse : au moment précis où la
policy stricte était restaurée, l'accès est retombé. Le journal, lui, disait autre chose —
voir ci-dessous. **Sans le journal, l'ACL était condamnée sur un enchaînement temporel.**

**🔴 Seconde cause, indépendante : le PORT DU PROXY DE SESSION n'est pas stable.**

```
dial tcp 127.0.0.1:43003: connect: connection refused
```

L'infrastructure de la session a redémarré (signe visible : les serveurs MCP se déconnectent puis
se reconnectent), et **le proxy de sortie a changé de port** — `43003` → `41577`. Or `tailscaled`
mémorise l'adresse du proxy à son démarrage : il perd sa sortie, puis meurt. La console avec.

⇒ **Après tout redémarrage de l'infrastructure, relancer console PUIS `tunnel_up.sh`.** Ce n'est
pas rattrapable dans le script tel quel : il faudrait surveiller `$HTTPS_PROXY` et redémarrer
tailscaled quand il bouge. Noté comme travail restant.

⚠️ Et pour l'enquête : `tailscale ping` du pair vers nous est **soumis à l'ACL** — la règle
n'ouvrant que `:443`, un ping échoue même quand tout fonctionne. Diagnostiquer avec `ping`
revient à utiliser un outil que la policy bloque, et son échec ne prouve rien.

### Le fichier de policy, et deux pièges de syntaxe

La policy retenue est archivée en clair dans [`tailscale-policy.hujson`](tailscale-policy.hujson)
— **copie de référence, rien ne l'applique automatiquement**. Elle ne contient aucun secret.

⚠️ Deux erreurs qu'on refera si on ne les note pas :

* **`autogroup:member` est interdit en `dst`.** Seuls `autogroup:self` et `autogroup:internet`
  y sont valides. En `src`, en revanche, `autogroup:member` va très bien.
* **`autogroup:self` ne couvre QUE les appareils appartenant à un utilisateur** — une machine
  taguée n'en fait jamais partie. C'est ce qui exclut la VM de tout le reste sans qu'on ait à
  l'écrire, et c'est aussi pourquoi elle a besoin de sa propre ligne.

⚠️ **Identité GitHub** : sur un tailnet où l'on se connecte par GitHub, un utilisateur s'écrit
`username@github` et non par son adresse e-mail. La valeur exacte est affichée dans
**admin console → Users** ; ne pas la deviner, la casse compte.

⚠️ **La règle `{"src": ["*"], "dst": ["*:*"]}` du fichier d'exemple annule tout.** Poser un tag
sans la retirer donne l'identité séparée et le key-expiry désactivé, mais **aucune isolation
réseau**. Le bloc `tests` est le garde-fou : une assertion qui échoue fait REFUSER
l'enregistrement. Et rassurant dans tous les cas — les ACL ne gouvernent pas l'accès à la console
d'admin, donc une policy catastrophique se corrige depuis le navigateur.

---

## 3 quater. 🔴 L'allowlist d'hôtes est revenue — et le réglage d'environnement n'a pas atteint la session (mesuré le 19/08/2026)

Mission du jour : monter le nœud Tailscale de la VM. **Résultat : nœud NON monté, arrêt à la
sonde d'egress.** Mais la sonde a mesuré trois choses qui valent la panne.

### ⭐ Troisième état du filtre d'egress : une passerelle TLS qui filtre PAR HÔTE

Le §3 bis notait déjà que la politique réseau est un réglage d'environnement, avec deux états
observés : allowlist d'hôtes le 01/08, hôtes arbitraires relayés le 02/08. Le 19/08 en montre un
**troisième**, plus instrumenté que le premier :

| Mesure 19/08 | Résultat |
|---|---|
| `curl --noproxy '*' https://controlplane.tailscale.com/key?v=138` (dial « direct », 443) | **HTTP 403** en ~40 ms, corps explicite : `Host not in allowlist: controlplane.tailscale.com. Add this host to your network egress settings to allow access.` |
| Même cible via `$HTTPS_PROXY` | `curl: (56) CONNECT tunnel failed, response 403` |
| Certificat présenté sur le dial « direct » | `CN=*.tailscale.com`, mais **issuer `O=Anthropic; CN=Egress Gateway SDS Issuing CA (production)`** |
| `github.com` (le `git fetch` du début de session) | ✅ passe |
| `recentRelayFailures` après ces 403 | **`[]`** — l'angle mort de l'errata 6, reconfirmé |

> ⭐ **Il n'y a plus de « hors proxy ».** Le 02/08, contourner `HTTPS_PROXY` en dial direct
> donnait le filtre de ports nu (§3 bis). Le 19/08, le dial direct en 443 aboutit sur une
> **passerelle TLS Anthropic qui termine la connexion elle-même** : elle forge un certificat au
> nom de l'hôte visé (signé par la CA du bundle `/root/.ccr/`, présente dans le store système,
> d'où un `curl` sans `-k` qui passe), lit le SNI, et répond 403 avec le nom de l'hôte refusé.
> Le message dit le mécanisme : le filtrage est **par hôte**, configurable par l'utilisateur
> (« your network egress settings »), et s'applique **aux deux chemins** — proxy et direct.

### 🔴 Le réglage ajouté par Eliott n'a pas atteint cette session

Contexte de la mission : Eliott venait d'ajouter `*.tailscale.com` aux Network egress settings
de l'environnement, et `TS_AUTHKEY` aux variables. **Cette session, pourtant démarrée après,
ne voit ni l'un ni l'autre** : le 403 ci-dessus, et `TS_AUTHKEY` absent de l'environnement
(vérifié sans afficher de valeur ; le hook `SessionStart` l'avait déjà signalé à 07:12).

Deux hypothèses, **non départagées** — les écrire toutes les deux est la leçon de l'errata 1 :

1. *(a)* allowlist **et** variables sont photographiées à un instant antérieur au réglage —
   VM provisionnée avant, ou propagation différée côté Anthropic ;
2. *(b)* le réglage n'a pas été enregistré ou ne s'applique pas à cet environnement-ci
   (plusieurs environnements existent, le réglage est par environnement).

Le fait que **les deux** réglages manquent **ensemble** penche vers une photographie unique
prise trop tôt *(a)* — cohérent avec le §3 ter (« une variable ne prend effet qu'à la NAISSANCE
d'une VM ») étendu à l'allowlist — mais ne prouve rien contre *(b)*. ⇒ **Prochain essai : une
session neuve, ouverte nettement après le réglage, qui relance la même sonde avant toute autre
chose.** Si le 403 persiste, c'est *(b)*, et c'est le réglage qu'il faut inspecter, pas la VM.

### ⚠️ Méta : le relevé du 19/08 de la session précédente n'a jamais été poussé

La mission faisait référence à un « erratum du 19/08 » établissant la passerelle par hôte.
**Aucune trace dans le dépôt** — la session qui l'a établi ne l'a pas poussé, et son relevé
est perdu avec sa VM. La règle « push = survie » (§2) ne souffre aucune exception, y compris
pour les sessions qui documentent la règle. Le présent paragraphe reconstruit le constat à
partir de mesures refaites, pas du souvenir.

### ⭐ 19/08, seconde session : hypothèse *(b)* tranchée — les réglages réseau sont PAR ENVIRONNEMENT (mesuré le 19/08/2026)

Le « prochain essai » ci-dessus a eu lieu le jour même, mais dans un **autre environnement** :
la session du matin tournait dans « PXL cloud », celle-ci dans « PXL Cloud All-Access ⚠️ ».
Résultat : **c'était *(b)*** — le réglage ne s'applique qu'à l'environnement où il est posé.
Ce que chaque environnement voyait, à quelques heures d'écart, même dépôt, même mission :

| Mesure | « PXL cloud » (matin) | « PXL Cloud All-Access ⚠️ » (cette session) |
|---|---|---|
| `TS_AUTHKEY` | absent | **présent** (61 caractères, non affichée) |
| `curl --noproxy '*' https://controlplane.tailscale.com/key?v=138` | 403 `Host not in allowlist` | **200**, JSON des clés publiques, ~100 ms |
| `https://example.com/` (hôte sans rapport) | *(non sondé)* | **200** — donc pas d'allowlist restrictive ici, pas seulement `*.tailscale.com` ajouté |

> ⭐ **La passerelle TLS Anthropic est là dans LES DEUX cas.** Même sur la connexion qui
> *réussit*, l'issuer du certificat de `controlplane.tailscale.com` est
> `O=Anthropic, CN=Egress Gateway SDS Issuing CA (production)` (mesuré à l'`openssl s_client`).
> All-Access ne retire pas la passerelle : il change sa **politique** (relayer au lieu de 403).
> Tout l'egress reste terminé-réinspecté ; Tailscale traverse ce MITM parce que la CA Anthropic
> est dans le store système — control plane comme DERP parlent TLS standard en 443.

**Le nœud est monté** (mission accomplie, contrairement au matin) :

- `claude-vm-pxl-tape.tailaee5f.ts.net` · `100.71.98.107` · `tag:pxl-vm` · relais home `par`
  (région 18, forcée par `tunnel_up.sh` §4 bis ; elle était déjà `par` avant le forçage, le seul
  pair en ligne y étant).
- ⚠️ Fait daté qui **contraste avec le §3 ter** : le hook avait enregistré le nœud sous
  `pxl-console` ; un **renommage à chaud** `tailscale set --hostname=claude-vm-pxl-tape` a fait
  suivre le `DNSName` en quelques secondes, sans suffixe `-1` et sans logout. Le DNSName figé du
  §3 ter concernait la **reprise d'un nom d'homonyme supprimé** — un renommage vers un nom libre,
  lui, se propage. Deux situations, deux comportements ; ne pas généraliser l'un à l'autre.
- ⚠️ La console ne répondait pas sur 8710 (`curl` local → connexion refusée, le hook l'avait
  signalé à 07:16) ; `serve` a été publié quand même — l'URL existera dès qu'un processus
  écoutera. Non bloquant, conforme à la mission.

### ⭐ 19/08, troisième session : le réglage re-posé a ATTEINT « PXL cloud » (mesuré le 19/08/2026, session de 07:17)

Après le constat *(b)* ci-dessus, Eliott a re-modifié les réglages de l'environnement
« PXL cloud » ; une session neuve y a été ouverte à 07:17 pour en prendre la photo. Cette
fois **tout y est** — même environnement que la session bloquée de 07:12, une heure d'écart :

| Mesure (« PXL cloud », 07:17) | Résultat |
|---|---|
| `TS_AUTHKEY` | **présent** (61 caractères, non affichée) |
| `curl --noproxy '*' https://controlplane.tailscale.com/key?v=138` | **200**, JSON des clés publiques |
| `https://example.com/` (hôte sans rapport) | **403** `Host not in allowlist` — l'allowlist est **restrictive** ici |
| Issuer du certificat de `controlplane.tailscale.com` | `O=Anthropic, CN=Egress Gateway SDS Issuing CA (production)` |

> ⭐ Les deux environnements ont donc des **politiques différentes derrière la même
> passerelle** : « PXL cloud » = allowlist par hôte (seuls les hôtes ajoutés passent),
> « All-Access » = tout relayé. Et le blocage de 07:12 n'était ni *(a)* ni tout à fait *(b)*
> tel qu'écrit : le re-réglage par Eliott a suffi, une session neuve du **même** environnement
> voit la nouvelle allowlist. Ce qui reste vrai du §3 ter : la photo se prend à la naissance
> de la VM — la session de 07:12, née avant le re-réglage, ne l'a jamais vue.

**Le nœud est monté — et le hook l'avait monté TOUT SEUL avant la mission** : à 07:18,
`session_start.sh` a déroulé téléchargement des binaires, auth par clé, forçage DERP et
`serve` en ~36 s à froid, sans intervention — première exécution de bout en bout du mécanisme
du §3 ter dans une VM neuve, sous `pxl-console` (le défaut du script).

- Renommage demandé par la mission : `tailscale logout` puis `TS_HOSTNAME=claude-vm-pxl-tape
  bash tunnel_up.sh` (la manœuvre du §3 ter) → **`claude-vm-pxl-tape-1.tailaee5f.ts.net`** ·
  `100.70.195.54` · `tag:pxl-vm` · relais home `par` (région 18, forcée par §4 bis).
- ⚠️ Le suffixe `-1` est la **contre-épreuve du renommage à chaud de la session jumelle**
  (ci-dessus) : elle avait pris `claude-vm-pxl-tape` nu vers 07:16, mon enregistrement de
  07:20 a trouvé le nom occupé. Le `HostName` s'affiche nu (`claude-vm-pxl-tape`) mais le
  `DNSName` garde `-1` — exactement le comportement figé du §3 ter. Les deux lectures se
  complètent : renommage vers un nom **libre** → le DNSName suit ; enregistrement sur un nom
  **pris** → `-1` pour la vie du nœud.
- ⚠️ Le nœud jumeau (`100.71.98.107`) n'apparaît **pas** dans ma liste de pairs quelques
  minutes après — évaporé avec sa VM (éphémère), ou masqué par l'ACL entre nœuds tagués :
  non départagé, et un `-1` à 07:20 prouve seulement que le nom était pris *à cet instant-là*.
- ⚠️ Console 8710 morte ici aussi, pour une cause différente de la jumelle : le hook lance
  `node /home/user/PXL-Switcher/console/server.mjs` et **ce dépôt n'est pas dans cette VM**
  (`MODULE_NOT_FOUND`). `serve` publié quand même — non bloquant.

## 3 quinquies. ⭐⭐ Veiller sur une boîte MBX depuis une VM (ajout du 22/08/2026)

*Demande d'Eliott : « garde toujours un monitoring ouvert sur MBX ». Le courrier de la tour
arrive quand il arrive ; une session qui ne regarde qu'entre deux tours doit être **réveillée**,
pas sondée à la main.* Script : `mbx_veille.sh`.

**Le mécanisme, en une phrase** : une **tâche harnais** qui sort dès qu'il y a du courrier —
**sa terminaison EST la notification**, puisqu'une tâche suivie réveille la session en se
terminant. C'est le garde-fou des labos de la nuit du 19-20/08 (« une mort du process réveille
la session »), appliqué au courrier.

🔴 **En tâche harnais, JAMAIS en `nohup` détaché** : le recyclage tue un détaché en vol, et
personne ne l'apprend. ⚠️ Et ça ne maintient pas le conteneur en vie — le § 2 l'a mesuré : la
tour avait un Monitor persistant et son conteneur a redémarré quand même. La veille survit à un
recyclage parce qu'elle se **relance**, pas parce qu'elle dure.

### Les trois règles, et chacune vient d'un défaut payé le 22/08

1. 🔴 **On PEEK, on ne draine JAMAIS.** `GET /api/turbohq/mbx/<boîte>` sans `?drain=1`. Drainer
   vide la boîte : si la VM meurt entre la lecture et le traitement, le message est perdu **et
   rien ne le dit**. La boîte du pair distant est la source de vérité et elle survit à cette VM.
   Le drain devient un geste conscient, au traitement — exactement la correction que MBX v2 a
   apportée avec ses curseurs (`MBX_V2_BRIEF.md` § 4).

2. 🔴🔴 **« Vivant » ne veut pas dire « fonctionnel » — on teste la FONCTION, jamais `pgrep`.**
   Trois fois en une heure le même jour : *(a)* `tunnel_up.sh` annonce **« nœud déjà
   authentifié »** sur un nœud `Online: False` avec un `AuthURL` en attente — sa garde teste que
   le démon RÉPOND, pas que le nœud est ENREGISTRÉ (remède : `up --force-reauth`) ; *(b)* le pont
   TCP dont le processus vit pendant que `tailscaled` est **mort** ; *(c)* `tailscaled` vivant
   avec une **socket périmée**. `pgrep` répond « oui » aux trois. La veille ne pose qu'une
   question — *est-ce que le courrier arrive ?* — et remonte le pont sur la réponse.
   ⚠️ **Corollaire pour tout ce dépôt** : `pgrep`/`status` disent qu'un processus EXISTE ; seule
   une requête dit qu'il SERT. C'est le motif 9 de `MISTAKE.md` (annoncer un état non vérifié) en
   version infrastructure — *et c'est Eliott qui l'a vu avant moi, en disant simplement « je ne
   te vois pas sur tailscale ».*

3. ⏳ **Bornée, et elle le DIT.** Au bout de N minutes (défaut 50) elle rend la main avec
   « borne atteinte, relancer » — ce qui réveille la session, qui la relance. *Un veilleur qu'on
   croit vivant est pire qu'un veilleur absent* (leçon de la nuit : « un banc qui doit durer se
   relance, il ne se suppose pas vivant »).

### 🔴🔴 ERRATUM du 22/08, quatre heures après la rédaction ci-dessus — **la veille était AVEUGLE**

La première version comptait les messages par `(j.messages ?? j.msgs ?? []).length`. **La boîte
rend un TABLEAU NU.** Donc le compteur rendait **0 à chaque tour**, et la veille a tourné
sereinement au-dessus de **cinq** messages — dont un d'Eliott qui nous appelait par notre nom.

⭐ *Une veille qui ne peut pas voir son sujet ne dit pas « je ne vois rien », elle dit « il n'y a
rien ».* Et ce silence-là se lit comme une bonne nouvelle : c'est **exactement** le motif 2 de
`MISTAKE.md` (« un test qui ne peut pas trouver ce qu'il cherche »), appliqué à l'instrument même
qu'on venait d'écrire pour ne rien rater.

⚠️ **La forme n'avait jamais été MESURÉE** — elle avait été supposée, sur l'idée qu'une API rend
un objet enveloppant. Une commande la donnait :

```bash
curl -s --noproxy '*' "http://127.0.0.1:8099/api/turbohq/mbx/<boîte>" | head -c 80
# [{"ts":…,"from":"eliott","to":"all","text":"…","origin":"mbx-100.99.45.4-8080","seq":488}, …
```

**Trois corrections, et la troisième est celle qui vaut pour la suite :**

1. Le compteur accepte le **tableau nu** comme l'objet enveloppant.
2. Il distingue **« zéro message »** de **« je ne sais pas lire »** (`-1`) — et sur `-1` la veille
   **rend la main en criant**, au lieu de veiller dans le vide. *Ne pas savoir n'est pas une bonne
   nouvelle*, la règle du `POST_BUF_EMPTY` à −1 du dépôt d'à côté.
3. ⭐⭐ **La veille porte son CONTRÔLE** : `bash mbx_veille.sh --controle` donne au compteur cinq
   charges dont on connaît la réponse (tableau nu · boîte vide · objet · JSON illisible · forme
   inconnue) et vérifie qu'il les sépare. Aucun réseau, une seconde. **Sabotage vérifié** : l'ancien
   compteur rend `0` sur la forme réelle, donc le contrôle mord exactement là où il fallait.
   ⚠️ Et la boucle appelle **la même fonction** — la recopier en ferait deux, et le contrôle ne
   prouverait plus rien de ce qui tourne.

### ⭐ AJOUT du 22/08 08:35 — un pair HORS LIGNE n'est pas un pont cassé

Après six bornes calmes et **145 regards aboutis** chacune, la veille s'est mise à répéter
*« ⚠️ pont monté mais muet — claudevm-turbohq ne répond pas sur 8080 »*, quatre fois. Diagnostic :
la VM du pair était **hors ligne depuis 4 min** — son conteneur s'était fait recycler, exactement
comme le nôtre le fera.

🔴 **`ip_du_pair()` rendait une IP quand même** : `tailscale status` continue de lister un pair
hors ligne, avec son adresse. La veille remontait donc un pont vers une machine qui n'existe plus,
et **accusait le pont**. *Une machine listée n'est pas une machine joignable* — la règle 2 (« vivant
≠ fonctionnel ») appliquée non plus à un processus mais à un **correspondant**.

⇒ `ligne_du_pair()` lit la **ligne entière** et la veille nomme le bon coupable, avec l'âge :

```
🔴 « claudevm-turbohq » est HORS LIGNE au tailnet — offline, last seen 5m ago.
   Ce n'est PAS le pont : sa VM est tombée (recyclage éphémère). On réessaie au tour suivant.
```

⚠️ **Et ce n'est pas une panne** : c'est le régime normal de deux VM éphémères qui se parlent. Ce
qu'il fallait corriger n'est pas la connexion, c'est **ce que le témoin en dit** — sinon on passe
une heure sur son propre tunnel pendant que le correspondant dort. Même famille que le 507 du
disque côté console : *« pas réglé », « pas trouvé » et « pas là » sont trois pannes différentes.*
✅ Vérifié **contre la condition réelle**, pas contre un cas fabriqué — le pair était effectivement
tombé au moment de l'écriture.

### Deux pièges concrets, déjà payés

- ⚠️ **`pkill -f <motif>` TUE LE SHELL QUI L'APPELLE** quand le motif apparaît dans sa propre
  ligne de commande (`bash -c "… pkill -f pont.mjs …"`). Mesuré deux fois — le tour s'arrête sur
  un `exit 144` inexpliqué. On tue **par PID** (`ps -eo pid,args | awk '/[m]otif/'`, le crochet
  excluant l'awk lui-même).
- ⚠️ **Le pair se résout par NOM**, jamais par une IP en dur : l'IP survit tant que le
  `statedir` survit, le nom survit toujours. `tailscale status | awk '$2 == nom'`.

### Le pont, et pourquoi il faut en passer par là

L'egress est en **userspace-networking** : ni `curl` ni le proxy d'agent ne routent les `100.x`
(§ 3 bis). La seule voie sortante est `tailscale nc`. D'où un pont TCP local de dix lignes —
`127.0.0.1:8099` → `tailscale nc <pair> 8080` — que la veille **remonte elle-même** quand il ne
relaie plus. Le CLI `mbx` du dépôt PXL-TurboHQ parle alors normalement
(`MBX_URL=http://127.0.0.1:8099`).

```bash
bash mbx_veille.sh switch-dev claudevm-turbohq 50   # en TÂCHE HARNAIS (run_in_background)
```

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

> 🔴 ~~**Un dépôt ne peut pas être attaché à une session déjà lancée**~~ (rapporté par Eliott le
> 01/08 ; non vérifié de l'intérieur, `add_repo` n'ayant pas été appelé).
>
> ✅ **CORRIGÉ — mesuré de l'intérieur le 18/08, trois fois** : `add_repo` a attaché
> `PXL-TurboHQ` (accès push, **pushes vers master réussis** dans la même session),
> `PXL-Switcher` et `PXL-CC-over-AnthrVM` — clone, `register_repo_root`, lecture ET écriture,
> tout dans la session en cours. Le périmètre GitHub n'est PAS figé au démarrage.
> ⚠️ **La correction est précise, pas totale** : les trois dépôts attachés PRÉEXISTAIENT à la
> session. Le scénario du 01/08 — un dépôt **créé pendant** la session puis attaché — reste
> non vérifié (la création elle-même prend toujours 403, donc il faudrait une création humaine
> en cours de session pour trancher ; la propagation d'installation de l'App est un suspect
> plausible du refus d'origine). Erratum 6.
>
> **Conséquence, et c'est le piège** : les deux verrous se referment l'un sur l'autre. On ne peut
> pas créer un dépôt depuis la session ; et le dépôt créé à la main pendant la session **reste
> hors d'atteinte jusqu'à la session suivante**. Il n'existe donc **aucune séquence** qui, en une
> session, part de rien et aboutit à du contenu poussé dans un dépôt neuf.
> ⚠️ *18/08 : le second verrou est tombé pour les dépôts préexistants (voir plus haut) — le
> double-verrou ne tient plus que sur le scénario « créé pendant la session », non re-mesuré.*
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
| `node` 22 (`/opt/node22`), `python3`, `rustc`, `go` | **`ffmpeg`** en PATH → ⭐ **`apt-get update && apt-get install -y ffmpeg` MARCHE** (mesuré 18/08) : 6.1.1 **avec libx264, libx265, libopus**. ⚠️ Sans le `update` d'abord, l'install échoue sur des index périmés (404). Le binaire `/opt/pw-browsers/ffmpeg-*` reste le repli sans réseau |
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
| **VideoENCODER** (mesuré 18/08, `isConfigSupported`) | AV1 ✅ · VP9 ✅ · **H.264 ❌ · HEVC ❌** — et l'encodeur AV1 **n'émet PAS de `decoderConfig.description`** (flux auto-décrit ; tout muxeur doit synthétiser l'av1C) |
| **AudioEncoder** (18/08) | **Opus ✅ · AAC ❌** |
| **File System Access** (18/08) | ❌ `showDirectoryPicker` absent en headless — se mocke par `addInitScript` (write/close/getFile suffisent pour un banc d'enregistreur) |
| **getUserMedia** (18/08) | ✅ avec `--use-fake-device-for-media-stream --use-fake-ui-for-media-stream` — caméra + micro factices, pipeline WebCodecs complet dessus |
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
| **Bitstream/conteneur H.264-HEVC** | VM (**ffmpeg apt + x264/x265**, 18/08) | protocole, muxage, remux — `-err_detect explode -f null` fait foi. C'est ce qui a validé toute la chaîne thq-publish/record/ingest en vrais codecs |
| Vérité physique | **Machine locale** | H.264/HEVC **matériels**, GPU réel, NVDEC, timings, 4K |

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
| **Afficher un canvas WebGPU** (et donc tester un rendu à l'écran) | §6 piège 6 — présenter perd le device |
| **HEVC en WebCodecs** | §6 piège 7 — même le vrai Chrome ne l'embarque pas sous Linux |

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

8. ❌ **« Les variables d'environnement de l'environnement Claude Code sont l'endroit où poser
   la clé Tailscale. »** (03/08, §3 ter, écrit le soir — corrigé le lendemain matin en allant
   chercher le chemin d'interface exact, qu'on ne m'avait pas demandé de vérifier.)

   L'observation était juste : c'est bien le **seul** endroit du dispositif qui survive à un
   recyclage sans être un dépôt git. La conclusion ne l'était pas : j'en ai déduit que c'était
   donc l'endroit **sûr**, sans lire ce que le produit en dit. Il en dit le contraire —
   « no dedicated secrets store, so don't add API keys or other credentials » — et la boîte de
   dialogue affiche l'avertissement à l'écran, au moment même où on tape la valeur.

   **Leçon : « le seul endroit possible » n'est pas « un endroit prévu pour ça ».** Une
   élimination qui ne laisse qu'un candidat prouve qu'il est le dernier, pas qu'il convient.
   Quand l'élimination ne laisse rien de sûr, la réponse honnête n'est pas de promouvoir le
   moins mauvais au rang de solution : c'est de dire qu'il n'y a pas de coffre, et de déplacer
   l'effort sur la **réduction du rayon d'explosion** — ici, scoper la clé (éphémère, taguée,
   ACL) plutôt que prétendre la cacher.

   Aggravant, du même genre que l'errata 7 : la recommandation a été écrite **au moment de
   conclure la session**, quand rien n'invitait plus à vérifier. C'est exactement là qu'une
   affirmation non mesurée passe.

9. ❌ **« Le trafic entrant ne passe pas, donc c'est l'ACL. »** (03/08, soupçonnée deux fois,
   fausse les deux fois.) L'ACL était le seul élément qu'on avait changé, donc le suspect
   naturel — et le raisonnement s'est arrêté là au lieu d'aller lire ce que le nœud recevait
   VRAIMENT. `tailscale debug netmap` montrait, **pendant la panne**, la règle
   `pxl-aero → :443` présente et correcte.

   Aggravant, et c'est ce qui rend l'entrée utile : au moment précis où la policy stricte a été
   restaurée après un essai en allow-all, l'accès est retombé. Enchaînement temporel parfait,
   conclusion évidente — et fausse : le journal montrait `connection refused` sur le port du
   proxy de session, qui venait de changer. **Leçon : une coïncidence temporelle n'est pas une
   causalité, et le journal la départage en dix secondes.** C'est le même mécanisme que
   l'errata 1, où une opération avait été identifiée par son timing.

10. ❌ **Trois lectures de mesure trop rapides dans la même heure**, toutes dans le même sens :
   conclure depuis une observation partielle.
   *(a)* « le `403` prouve que l'isolation marche » — c'était la passerelle de sortie de la VM
   qui refusait une IP en plage réservée, la requête n'avait jamais atteint tailscaled.
   *(b)* « `tailscale nc` vers notre propre IP prouve que l'entrant fonctionne » — une connexion
   d'un nœud vers lui-même court-circuite le tailnet et le filtre ; ça ne prouvait que le
   listener et le certificat.
   *(c)* « `inbound_packets = 0` prouve que les paquets n'arrivent pas » — ce compteur ne compte
   que le trafic IP tunnelisé, pas le disco ; il était à 0 pendant que 120 pongs arrivaient.
   **Leçon : avant de conclure d'un compteur ou d'un code de retour, établir ce qu'il compte et
   ce qu'il ne compte pas.** Un zéro n'est une absence que si on sait ce qu'il mesure.

⚠️ **Les errata 11 à 15 viennent de la branche `claude/mesures-2026-08-18`, fusionnée le
29/08.** Ils portaient les numéros 6 à 10 chez elle : les deux lignes de travail ont numéroté
en parallèle, et **rien n'a été retiré de part et d'autre** — c'est la règle du dossier. Le
renumérotage est le prix du parallélisme, pas une réécriture.
🔴 **Et la branche portait une correction MAJEURE qui n'est pas dans cette liste** : l'egress
n'est plus filtré par PORT mais par **HÔTE** (passerelle TLS lisant le SNI) — c'est au § 3, pas
ici. L'errata 12 en est le corollaire : les réglages d'egress ne sont **pas** figés au démarrage.
Les deux sont restés un mois dans une branche non fusionnée — voir l'errata 16.

11. ❌ **L'erratum 3 s'est trompé dans l'autre sens.** « Le périmètre est figé au démarrage de
   la VM » — mesuré le 18/08 : **`add_repo` attache bel et bien des dépôts en cours de
   session**, trois fois, clone + register + pushes vers master compris. La correction du 01/08
   avait généralisé UN échec (un dépôt créé pendant la session) en une politique (« le périmètre
   est figé ») — sans mesurer l'attachement d'un dépôt préexistant, qui est le cas courant.
   **Leçon : corriger une erreur avec un énoncé plus large que la mesure qui le fonde, c'est
   préparer l'erratum suivant.** Le résidu exact qui reste non vérifié : attacher un dépôt créé
   PENDANT la session (propagation d'installation de l'App suspectée). Et l'environnement a pu
   changer entre le 01/08 et le 18/08 — les deux mesures peuvent avoir été justes chacune à sa
   date ; c'est indécidable rétroactivement, et c'est une raison de plus de dater tout.

12. ❌ **« Les réglages egress sont figés au démarrage de la session. »** (19/08, appuyé sur une
   sonde de 10 min restée en 403 après un ajout d'allowlist) Mesuré le 20/08 : **un ajout fait
   depuis l'interface WEB s'applique EN DIRECT aux sessions vivantes** — `pkgs.tailscale.com`
   puis trois hôtes d'heure sont passés de 403 à 200 en pleine session, sans redémarrage.
   Explication d'Eliott (à re-vérifier proprement un jour) : le comportement dépend de
   l'INTERFACE — un changement depuis l'appli mobile ne se propage pas aux sessions en cours,
   depuis le web si. La sonde du 19/08 mesurait donc probablement un ajout fait au mobile.
   **Leçon : « la config est figée » était encore un énoncé plus large que sa mesure — le
   chemin par lequel une config est modifiée fait partie des variables de l'expérience.**
   *Résidu du 20/08 :* la propagation web-en-direct n'est pas non plus uniforme — sur trois
   VM du même environnement, deux ont vu l'ouverture immédiatement, la troisième est restée
   en 403 **y compris après une re-sauvegarde** de l'environnement (re-testé 2×, 09:25:35Z).
   Aucune variable discriminante identifiée (même env, sessions du même matin). À re-mesurer
   au prochain recyclage de cette VM ; d'ici là, l'énoncé honnête est « s'applique en direct
   *souvent*, pas toujours ».

13. ❌ **`pkill -f` (et `pgrep -f`) se tuent eux-mêmes depuis un appel d'outil.** (22/08, payé
   DEUX fois dans la même séance — exit 144, le tour meurt net et tout ce qui suivait dans la
   commande composée n'a jamais tourné.) Le harnais lance chaque commande via
   `/bin/bash -c "<toute la commande composée>"` : la ligne de commande du shell CONTIENT donc
   le motif littéral (`pkill -f "server_turbohq.mjs 8080"` → le shell se matche lui-même).
   **Parades, par ordre de sûreté :** tuer par PID relevé AVANT (`ss -tlnp`, fichier PID) ;
   `pkill -x` (nom exact du binaire, pas la ligne) ; ou couper le motif dans le source pour
   qu'il n'apparaisse pas littéralement (`pgrep -f 'server_turbo''hq.mjs'` — le process node
   matche, la ligne du shell qui porte les quotes non). **Leçon : dans une VM harnais, le
   process le plus proche du motif est TOI.**

14. ❌ **Le `cd` en tête de commande composée casse tous les chemins relatifs qui suivent.**
   (Récidive au moins 5 fois entre le 19 et le 22/08 — « fatal: pathspec 'v3/turbohq' »,
   « diff: v3/turbohq: No such file ».) Le motif : `cd /workspace/<autre-dépôt> && … && node
   v3/turbohq_attach.mjs …` — l'outil d'attache et les diffs de contrôle sont écrits pour être
   lancés depuis `/home/user/PXL-Tape`. La variante VICIEUSE du 22/08 : l'attache masquée par
   `>/dev/null 2>&1` a échoué EN SILENCE — le resync n'avait juste pas eu lieu, seul le diff
   d'après l'a dit. **Parades : chemins absolus partout dans les composées ; jamais de
   redirection muette sur une étape qui conditionne la suite ; et le harnais remet le cwd à
   chaque appel (« Shell cwd was reset ») — un `cd` ne « reste » jamais, il ne fait que polluer
   la commande où il vit.**

15. ❌ **Un `&` shell ne survit pas fiablement à l'appel d'outil — seul `run_in_background`
    du harnais survit ET réveille.** (Même nuit, même famille que le n°8 : le guetteur MBX
    relancé par `… & sleep 1` était mort avant la fin de l'appel — la veille qu'on croyait
    armée ne l'était pas.) Nuance mesurée : un serveur `nohup … &` a survécu plusieurs fois à
    son appel — la mort n'est pas systématique, elle est INTERMITTENTE, ce qui est pire : un
    garde-fou qui « marche parfois » n'est pas un garde-fou. Et même survivant, un process
    shell ne réveille jamais la session ; la tâche harnais (`run_in_background: true`) survit
    et sa terminaison réveille — c'est LE mécanisme de veille. **Leçon : ce qui doit vivre
    après le tour, ou réveiller, se confie au harnais, jamais au shell.**

16. ❌ **« La branche `claude/mesures-2026-08-18` supprime 548 lignes du dossier — ne pas la
    fusionner. »** (22/08) **Faux, et c'est un diff lu à l'envers.** J'avais regardé un diff à
    **DEUX points** (`git diff HEAD..branche`), qui compare les deux SOMMETS : il affiche donc
    *nos propres ajouts* comme des suppressions, puisque la branche ne les a pas. Le chiffre
    était réel — 1944 suppressions au total, dont `tunnel_up.sh` et la policy entiers — et il ne
    décrivait rien de ce qu'une fusion aurait fait.
    ⭐ **Le diff à TROIS points** (`git diff HEAD...branche`, depuis la base commune) dit ce
    qu'une fusion fait vraiment : **+205 / −5**, uniquement des ajouts datés au dossier et au
    README. Exactement ce que la règle de rédaction prescrit.
    🔴 **Ce que ça a coûté** : un mois. La branche portait la correction majeure du § 3 —
    *l'egress est filtré par HÔTE, pas par port* — pendant que le `CLAUDE.md` de ce dépôt
    continuait d'annoncer **« TCP/80, TCP/443, UDP/53 »** à chaque session. Une mesure juste,
    poussée, et rendue invisible par un refus de fusion fondé sur un artefact d'affichage.
    **Leçon : `..` et `...` ne répondent pas à la même question.** Avant de refuser une fusion
    sur la foi d'un diff, vérifier lequel on lit — et se demander *« ces suppressions sont-elles
    les MIENNES ? »*, ce qui coûte une commande (`git merge-base`).
    ⚠️ C'est la famille du motif 8 de `MISTAKE.md` — *un outil mal employé qui juge mon modèle
    au lieu du sujet* — appliquée à `git` lui-même.

---

## 9. Sources

**Mesures** — `probes/vm_survey.sh` (01/08, rejouée le 02/08) · `probes/tunnel_probe.sh` (02/08,
`--full` pour lancer réellement les deux clients) · `add_repo` + clone de `pxl-airlink` et
`PXL-SPOUT-TurboHQ` en cours de session (02/08, §4 bis — pas de sonde : deux appels d'outil,
rejouables tels quels) · `probes/webgpu_probe.mjs`,
`probes/vram_probe.mjs` (25-26/07) · **`probes/webgpu_canvas_probe.mjs` (28/08)** ·
relevés de cycle de vie des 26-27/07, repris de
`PXL-Tape/v3/tests/investigations/note_vm_lifecycle.md`.

**Documentation** — [Claude Code on the web](https://code.claude.com/docs/en/claude-code-on-the-web)
(environnements, politiques réseau, triggers, sources) · `/root/.ccr/README.md` (proxy, dans la VM).

**Documents PXL liés** — `PXL-Tape/v3/tests/investigations/note_vm_lifecycle.md` et
`note_vm_webgpu.md` (les notes d'origine, dont ce dossier est la reprise et la correction) ·
`PXL-StageBox/jpegxs-arm/README.md` (le banc dont le §1 explique la non-reproductibilité).

## 🤝 « Rendez-vous plutôt que perçage » — le réseau inter-VM, doctrine (20/08)

Question d'Eliott : mettre les IP des VM dans l'allowlist egress pour
qu'elles se voient en direct ? **Non, trois verrous empilés** : (1)
l'allowlist est un FILTRE de sorties (noms de domaine), pas un routeur —
elle ne crée ni route ni écoute entrante ; (2) les conteneurs n'ont AUCUNE
porte d'entrée (IP privées non routables, rien n'écoute de l'extérieur) ;
(3) preuve empirique du 19/08 : le hole-punching tailscale — le meilleur
chercheur de chemin direct du métier — a fait 0 % de direct, 100 % DERP sur
toutes les paires. S'il existait un chemin, il l'aurait trouvé.

**La doctrine qui en découle : on ne perce pas les murs, on se donne
rendez-vous dehors.** Deux VM se « voient » via un point de rencontre
extérieur qu'elles joignent chacune EN SORTANT — et l'allowlist est
précisément la liste des lieux de rendez-vous autorisés. Trois
incarnations, du plus bas au plus haut niveau :
1. **DERP public Tailscale** (l'existant) : ~98 ms de plancher, files
   partagées, zéro contrôle.
2. **DERP À SOI sur le VPS OVH** (la recette prête pour le jour des clés) :
   le binaire officiel `derper` sur le VPS (une heure d'install), son nom
   de domaine dans l'allowlist (les clients DERP sortent en HTTPS/443 —
   pile ce que le proxy sait autoriser), déclaré dans la DERP map du
   tailnet (`derpMap` des ACL). Résultat : tout le trafic inter-VM passe
   par SON relais — latence d'un VPS bien placé, bande passante à soi,
   zéro changement dans les logiciels (tailscale route seul).
3. **Relais applicatif sur le VPS** (TurboHQ/MBX — le « relais désigné »
   du plan P2P) : mêmes propriétés au niveau flux.

C'est le même théorème que toute la semaine : pas de chemin direct → élire
un point de rencontre de qualité connue (le grandmaster pour l'heure, le
relais pour les flux, le DERP à soi pour le tailnet).
