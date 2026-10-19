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

**Ajout, 18/10 10:10 UTC (12h10 heure française) — l'horloge, mesurée : pas de NTP, juste quand même, et en UTC
(session TurboHQ ; question d'Eliott : « est-ce que la VM a du NTP ? je dois ajouter 2 h à chaque fois »).**

| | Mesuré |
|---|---|
| Démon NTP | **aucun** (ni `chronyd`, ni `ntpd`, ni `systemd-timesyncd` ; `timedatectl` présent mais pas de systemd) |
| Noyau | `adjtimex` : **STA_UNSYNC**, freq 0,000 ppm, tick 10000 — personne ne discipline l'horloge de l'intérieur |
| Source | `clocksource` = **tsc** (Firecracker) |
| Écart | **−0,07 s** contre l'en-tête `Date` du VPS `thq.pxl.re` (timesyncd), résolution 1 s, aller-retour 0,84 s — après **29,9 h** sans démon (VM bootée le 17/10 04:37:34 UTC, le vrai reboot du 5e redémarrage, §2) |
| Écart, seconde référence | **+1,09 s** contre `pypi.org` (la sonde, 10:35 UTC, aller-retour 1,52 s). Les deux références se contredisent de 1,2 s : la méthode (en-tête `Date`, à la seconde, derrière un aller-retour d'une seconde) ne vaut pas mieux que **±1 s**. « Juste à la seconde » est tout ce qu'elle peut dire — pas « −0,07 s » |
| Fuseau | `/etc/localtime → Etc/UTC`, `TZ` vide ; `tzdata` complet (`Europe/Paris` présent) |
| Le réseau PXL | pxl-tx et la box sont en **Europe/Paris** (la box : `timedatectl` Europe/Paris, `date` CEST ; `/etc/timezone` y dit encore `Etc/UTC`, fichier périmé). Ce sont les **sessions** qui écrivent en UTC dans MBX et les journaux, pas les machines |

- **Lecture** : l'heure est juste à la seconde sans qu'aucun service ne la tienne — l'hôte la pose au démarrage de la
  microVM, et 30 h plus tard elle n'a pas bougé de plus de 0,5 s (< 5 ppm, ou l'hôte la retient : **supposé**, kvm-clock
  ou le tsc de l'hôte ; non distingué). Rien ne se mesure dans la VM : ça suffit. On ne peut pas y mettre NTP
  (pas de systemd, et `adjtimex` en écriture demanderait CAP_SYS_TIME — **non essayé**, inutile).
- **Les 2 h sont le fuseau, pas la synchro.** Remède durable : la variable d'environnement **`TZ=Europe/Paris`** dans
  les réglages de l'environnement cloud (menu de l'environnement dans la barre de titre → Edit) — chaque nouvelle
  session la prend — ou, dans le script de configuration de l'environnement, `ln -sf
  /usr/share/zoneinfo/Europe/Paris /etc/localtime`, qui ne dépend d'aucun shell. ⚠ `~/.bashrc` ne sert à RIEN ici :
  le shell de l'outil Bash ne le lit pas (mesuré le 18/10 : `export TZ` posé dedans, `date` répondait toujours en
  UTC). Pour la session en cours, le lien `/etc/localtime` (root) fait l'affaire : posé le 18/10 dans cette VM,
  `date`, Python et Node répondent en heure française aussitôt. ⚠ Corollaire : `uptime -s` et `date` sans `-u` parlent
  alors en heure française — `vm_survey.sh` convertit explicitement (section Horloge ajoutée, et le canari dit
  « UTC » à raison).

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

### 15/10/2026 — une veille qui tient quand personne ne parle (session TurboHQ, mesuré)

Contexte : la session « TurboHQ » de PXL-TurboHQ veille une boîte aux lettres (MBX, sur une machine du tailnet) par
une tâche de fond qui SORT dès qu'un message arrive, pour réveiller la session, qui la réarme ensuite.

| Fait | Mesure |
|---|---|
| Fin d'une tâche suivie, **aucun tour en cours** | 🔴 **n'a PAS réveillé la session**. Deux fins (13:35:05 et 13:38:55 UTC, la seconde une veille sortie sur courrier), aucun tour. Le suivant n'est venu qu'avec un message humain, à 14:56 |
| La VM de 14:56 | **neuve** (PID ~200). `tailscaled` en espace utilisateur « Logged out » (NeedsLogin), alors que son état (`~/.ts`) avait survécu. `tailscale up --authkey="$TS_AUTHKEY"` le rétablit aussitôt : la variable est bien présente dans l'environnement de la VM neuve |
| Ce qui a survécu au recyclage | `/home/user` (dépôts, `~/.pxl`, `~/.ts`) et le scratchpad, comme au §2 |
| `sleep` au premier plan | refusé par le harnais (« use Monitor … or run_in_background ») |
| Tâche planifiée côté serveur (`create_trigger`, tir **dans** la session) | créée à 15:09:33 UTC. Un cron horaire `0 * * * *` est ancré sur la minute de création : il devient `9 * * * *`. Premier tir attendu à 16:09 UTC — **à mesurer**. Supposé : il ressuscite la session comme `send_later` le 27/07 |

**Ajout, 15/10 18:07 UTC — le tir de la tâche planifiée est mesuré.** Elle a tiré à **16:10:44** et **17:10:48 UTC** :
cron `9 * * * *`, donc **1 min 44-48 s après la minute prévue** (délai de file, constant sur deux tirs). Son prompt
arrive dans la **même session**, comme un message ; les deux fois la veille battait (fichier de battement < 3 min),
réponse « Veille MBX : OK ». Toujours **non mesuré** : un tir sur une VM recyclée — aucun recyclage depuis 14:56.

⚠️ **Divergence avec le 27/07**, où la complétion avait réveillé la session : constatée, pas expliquée. C'est un fait
nouveau, pas un erratum, car rien ne dit que la mesure du 27/07 était fausse.
⇒ Règle 3 appliquée : la veille est doublée d'une **tâche planifiée horaire** qui la relance si elle est morte.
Le dispositif et ses outils sont versionnés dans PXL-TurboHQ, `deploy/claudevm/` :
- `tunnel_assure.sh` : `tailscaled` détaché et ré-authentifié ;
- `veille_mbx.sh` : la veille ;
- le README : les deux moitiés du dispositif, et les pièges déjà payés.

### 16/10/2026 01:05 UTC — un redémarrage du conteneur EN PLEINE SESSION, tâche suivie en cours (session TurboHQ, mesuré)

| Fait | Mesure |
|---|---|
| Instant | entre le dernier battement de la veille MBX (01:04 UTC, fichier touché toutes les 60 s) et `uptime` = 0 min à 01:05:36 |
| La tâche suivie en cours (la veille) | **tuée**, et le harnais l'a **dit** : « The container was restarted … task be2jqwazk … now stopped. Re-create them if still needed » — comme le 11-12/09 (§3 bis) |
| Réveil | 🟢 **le redémarrage a réveillé la session** sans message humain : un tour est parti avec la notification des tâches perdues (premier ordre à 01:05:20). À rapprocher du 15/10 13:35, où la simple FIN d'une tâche n'avait réveillé personne |
| Ce qui a survécu | `/home/user` : les trois dépôts à leurs commits, sans modification ; le fichier de battement ; `~/.ts` |
| Ce qui est mort | `tailscaled` (aucun processus). `tunnel_assure.sh` l'a relancé, et la veille relancée lisait le courrier dès 01:05:53 |
| Courrier | rien de perdu. La boîte MBX garde le courrier jusqu'au `read` : un message posé à 01:05:13, PENDANT le redémarrage, a été lu au premier tour de la veille relancée |
| Machine après redémarrage | Firecracker, Xeon @ 2,80 GHz, 4 cœurs, 15 Go, AVX-512, 29 Go libres. **Noyau 6.18.44-fc-v114** (§1 a relevé 6.18.5) : une divergence de plus, datée ici sans toucher au §1 |
| Canari | absent, parce que jamais posé dans cette session. Posé à 01:05:36 : c'est lui qui datera le prochain redémarrage |

⇒ Pour la règle 2 : une tâche suivie tient la VM contre le recyclage d'**inactivité** (§2), pas contre un **redémarrage** du
conteneur. Ce qui doit survivre vit dans `/home/user` ou dans un service distant, comme la boîte MBX.

**Ajout, 16/10 02:05 UTC — un SECOND redémarrage, une heure après, et le workdir change de silicium.** Le dernier
battement de la veille est à 02:03:21, et `uptime` donne 0 min à 02:03:51. ⭐ Le canari posé à 01:05:36 est **présent**,
avec sa ligne « VM bootée à 01:04:58 », et les trois dépôts sont à leurs commits : le workdir a survécu. Mais la
machine n'est plus la même :

| | 01:05 UTC | 02:03 UTC |
|---|---|---|
| CPU | Xeon @ **2,80 GHz** | Xeon @ **2,10 GHz** |
| Noyau | 6.18.44-fc-**v114** | 6.18.44-fc-**v139** |
| Cœurs | 4 | 4 |

⇒ Le « CPU qui change d'une session à l'autre » du §1 change aussi **à l'intérieur d'une session**, d'un redémarrage
à l'autre : le même `/home/user` est remonté sur un autre hôte. Corollaire, plus fort que la règle du §1 : une
mesure de perf n'est même pas comparable à une mesure de la même session si un redémarrage les sépare. Le canari
(`uptime` et sa date de boot) suffit à le savoir. `tailscaled` était de nouveau mort, et la veille a été relancée.

**Ajout, 16/10 15:02 UTC — un TROISIÈME « redémarrage du conteneur », SANS redémarrage de la VM, et le port du proxy
change sous les processus survivants (session TurboHQ, mesuré).** Le harnais annonce le même message qu'à 01:05 (« The
container was restarted … task bi1gj4qd5 … now stopped ») et réveille la session. Le dernier battement de la veille est
à 14:59:48, et le premier ordre part à 15:00:50. Mais cette fois-ci :

| Fait | Mesure |
|---|---|
| `uptime -s` | **02:03:30**, inchangé : pas de reboot. Même noyau (v139), même Xeon @ 2,10 GHz, 4 cœurs |
| Canari | présent, et les deux dépôts sont à leurs commits |
| Processus hors harnais | **vivants** : `tailscaled` (PID 221, lancé après le reboot de 02:03) tourne toujours, sans orphelin de la veille |
| Tâche suivie (la veille) | tuée et signalée, comme à 01:05 et 02:03 |
| ⭐ Port du proxy | **39833 → 43071**. `tailscaled` garde dans son environnement l'ancien `HTTPS_PROXY` (lu dans `/proc/221/environ`) |
| Effet | tunnel **mort en silence**. Le nœud lui-même est « offline » dans `tailscale status`, `tailscale ping` vers pxl-tx ne répond pas, et le SOCKS5 refuse la connexion. Pourtant `BackendState` vaut **« Running »** : `tunnel_assure.sh`, qui ne regarde que la présence du processus et cet état, a conclu que tout allait bien |
| Remède | `kill` de `tailscaled`, puis `tunnel_assure.sh` le relance avec le port courant : pong vers pxl-tx via DERP en 124 ms |
| Courrier | rien de perdu : la boîte MBX était vide au `read` |

⇒ Le « port aléatoire par session » du §3 change aussi **à l'intérieur d'une session**, sans reboot. Un « redémarrage
du conteneur » n'est donc pas un seul événement : ici, la VM et ses processus survivent, mais l'agent et son proxy
repartent. Tout processus qui a lu `HTTPS_PROXY` à son démarrage pointe alors sur un port mort. Corollaire pratique :
`BackendState: Running` ne prouve pas que le tunnel marche. Le test qui fait foi est un `tailscale ping` vers un pair,
ou la comparaison du `HTTPS_PROXY` du processus avec le courant. `tunnel_assure.sh` ne fait encore ni l'un ni l'autre
(correctif proposé à Eliott, pas posé).

**Ajout, 17/10 03:58 UTC — un QUATRIÈME redémarrage, de la même espèce : le mécanisme est reproduit.** Le dernier
battement de la veille date de 03:56:02, le premier ordre part à 03:57:40. Les mêmes constats qu'à 15:00 :
- `uptime -s` vaut toujours **02:03:30** : pas de reboot, même noyau v139, même Xeon @ 2,10 GHz ;
- le canari est présent (posé le 16/10 à 15:00:50) ;
- `tailscaled` (PID 26228) est vivant, mais reste sur le port de proxy d'AVANT : **43071 → 46741**. Le tunnel est donc
  mort sans le dire ;
- même remède : `kill`, puis `tunnel_assure.sh`, et pong vers pxl-tx via DERP en 116 ms. La boîte MBX était vide :
  rien de perdu.

⇒ Trois ports en 26 h sans reboot : 39833 → 43071 → 46741. Le port du proxy change à CHAQUE « redémarrage du
conteneur » de cette espèce, et ce n'est pas un accident isolé. Le correctif de `tunnel_assure.sh` (comparer le
`HTTPS_PROXY` de `tailscaled` au courant, ou faire un `tailscale ping`) attend toujours le go d'Eliott. D'ici là, le
réflexe après un réveil sur redémarrage est de lancer ces deux commandes avant de croire « Running ».

**Ajout, 17/10 04:38 UTC — un CINQUIÈME redémarrage, 40 min après le quatrième, et cette fois-ci un VRAI reboot.**
Le dernier battement date de 04:37:02. `uptime -s` donne **04:37:34** : la VM a redémarré, ce que les deux
précédents n'avaient pas fait.
- Le canari est présent et les dépôts sont à leurs commits : le workdir a survécu, comme à 01:05 et 02:03 le 16/10.
- Le noyau (v139) et le Xeon @ 2,10 GHz sont inchangés.
- `tailscaled` est MORT, puisqu'aucun processus ne survit au reboot. `tunnel_assure.sh` l'a relancé sur le port
  courant (42327), sans ré-authentification, et pxl-tx a répondu au ping via DERP en 162 ms. Boîte MBX vide.
⇒ Les deux espèces existent bel et bien, sous le MÊME message du harnais (« The container was restarted ») :
- le reboot, où tout meurt, `tailscaled` compris, et où `tunnel_assure.sh` suffit ;
- le redémarrage sans reboot, où les processus survivent mais où le port du proxy change : là, `tunnel_assure.sh`
  NE suffit PAS.
Seul `uptime -s` les distingue.

**Ajout, 17/10 17:35 UTC — un SIXIÈME redémarrage, sans reboot, et une précision sur « les processus survivent ».**
- `uptime -s` vaut toujours **04:37:34** : pas de reboot.
- Le port du proxy passe de **42327 à 41719**. `tailscaled` (PID 199) est vivant, mais il reste sur l'ancien port.
  Même remède : `kill`, puis `tunnel_assure.sh`. Boîte MBX vide.
- 🟡 **La précision.** La veille MBX, une tâche de fond SUIVIE par le harnais, n'a PAS survécu : aucun processus
  `veille_mbx` après le réveil, et le harnais l'annonce (« background tasks … are now stopped »). `tailscaled`, lancé
  HORS du harnais, a survécu, lui.
⇒ « Les processus survivent » ne vaut que pour les démons lancés hors du harnais. Ses tâches de fond, il les arrête
lui-même. Après un réveil de cette espèce, il faut donc relancer la veille ET réparer le tunnel.

**Ajout, 18/10 06:31 UTC — un SEPTIÈME redémarrage, sans reboot, et un détail sur la relance du tunnel.**
- `uptime -s` vaut toujours **04:37:34** (le 17/10) : pas de reboot. Le canari est présent : le workdir a survécu.
- Le port du proxy passe de **41719 à 43537**. `tailscaled` (PID 23907) est vivant, mais sur l'ancien port :
  `tx_ssh.py` reçoit « SOCKS refuse la connexion ». Même remède : `kill` (PID exact, ligne de commande vérifiée),
  puis `tunnel_assure.sh`.
- 🟡 **Le détail.** Lancé juste après le `kill` (10 s d'attente au plus), `tunnel_assure.sh` n'a rien imprimé, et
  aucun `tailscaled` ne tournait après lui. Un second appel a suffi : « Running », et pxl-tx répond. Cause non
  établie [H : le processus tué n'avait pas encore disparu quand le `pgrep` du script l'a cherché, d'où pas de
  relance]. Réflexe : après le `kill`, vérifier qu'aucun `tailscaled` ne reste, relancer, puis vérifier
  `tx_ssh.py "echo ok"` avant de réarmer la veille.
- La veille MBX, tâche suivie, est morte avec le redémarrage, comme le 17/10 à 17:35. Relancée à 06:33. Les messages
  arrivés entre-temps restent dans la boîte : la veille les lit dès son départ.

---

**Ajout, 18/10 17h12 (heure française ; 15:12 UTC) — un HUITIÈME redémarrage, et un VRAI reboot (le 2e de cette
espèce, après le 5e).** Dernier battement de la veille à 17:10:17 CEST ; `btime` (/proc/stat) = **15:10:43 UTC**
(17:10:43 CEST), uptime 0 min au réveil. Comme au 5e : **le disque a tout gardé** — le canari du 06:31 UTC, les
dépôts à leurs commits, et aussi `/etc/localtime → Europe/Paris` et `~/.bashrc` posés 4 h plus tôt (la VM se
réveille en heure française) ; **tout processus est mort** — `tailscaled` (0 processus), la tâche de fond de la
veille (le harnais le dit) ; **le port du proxy a changé**, 43537 → 33019. `tunnel_assure.sh` UNE fois a suffi :
« Running », SSH sur pxl-tx 90 s après le réveil (17:12:16 CEST). ⚠ C'est à ce réveil que la sonde a montré son
propre bug (erratum 12) : « boot 17:10:43 UTC » pour une VM bootée à 15:10:43 UTC.

**Ajout, 19/10 03h51 (heure française ; 01:51 UTC) — un NEUVIÈME redémarrage, vrai reboot encore, 10 h 40 après le
huitième.** Dernier battement de la veille 03:50:44 CEST ; `btime` = **01:50:56 UTC** (03:50:56 CEST), uptime 0,5 min au
réveil. Même espèce que le 8e : disque gardé (canari du 15:13 UTC, `/etc/localtime` Paris, dépôts à jour), processus
morts (`tailscaled` 0, la tâche de fond de la veille), **port du proxy 33019 → 38323**. `tunnel_assure.sh` une fois :
« Running », SSH sur pxl-tx à 03:51:42 (46 s après le réveil). La sonde corrigée (btime) donne le bon boot du premier coup.
Deux vrais reboots en 11 h après deux jours sans : la fréquence varie, rien ne l'annonce.

**Ajout, 19/10 16h50 (heure française) — un DIXIÈME redémarrage, SANS reboot (uptime 777 min, même `btime`), 13 h après le
neuvième.** Dernier battement 16:47:27 CEST ; **port du proxy 38323 → 39581** ; `tailscaled` vivant (1 processus) mais
PÉRIMÉ : `tunnel_assure.sh` répond « Running » et pourtant `tx_ssh.py` échoue (« SOCKS refuse la connexion ») — l'espèce
du 6e et du 7e, reproduite. Remède : tuer `tailscaled`, puis `tunnel_assure.sh` — UNE fois a suffi cette fois (deux le 7e),
SSH sur pxl-tx 35 s après le réveil. ⚠ Piège rencontré en le faisant : `pkill -f 'tailscaled --tun=…'` a tué **le shell
de l'outil lui-même** (code 144 = SIGTERM) — la commande qui cherche contient le motif, la leçon du battement (§2, 15/10)
vaut aussi pour `pkill` : écrire `'[t]ailscaled --tun=…'`. Le correctif de `tunnel_assure.sh` (comparer le proxy de
`tailscaled` au courant, ou un `tailscale ping` avant de dire « Running ») attend toujours le go d'Eliott.

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

### 3 bis. Mesures des 11-12/09/2026 — ce que le tunnel laisse passer, exactement

Session « maître du VPS » (relais TurboHQ à installer sur un VPS OVH). Tout mesuré.

| Test | Résultat |
|---|---|
| `CONNECT 51.77.202.113:22` (et 65222, 80, 8080…) | **`200 Connection Established`**, puis silence, puis **403 à la première écriture** |
| `CONNECT github.com:80` — hôte autorisé, port ouvert | **identique** : 200, silence, 403 à l'écriture |
| `CONNECT github.com:5201` — port fermé | identique |
| `CONNECT 51.77.202.113:443` | **403 dès le CONNECT** (hôte hors allowlist) |
| `CONNECT mpv.io:443` (témoin) | 403 dès le CONNECT |

⭐ **Le `200` du CONNECT est optimiste et ne signifie rien.** La politique s'applique à la
**première écriture**. Et la règle réelle est plus étroite que « hôte autorisé » : le tunnel
ne passe que **du TLS sur 443 vers un hôte autorisé**. Un port autre que 443, même vers
`github.com`, est refusé. **SSH ne traversera jamais ce proxy**, quoi qu'on ajoute à
l'allowlist. Le témoin `github.com:80` est ce qui l'a prouvé : sans lui, le VPS aurait
été accusé à tort (errata 6).

**Le seul chemin vers une machine tierce : le tailnet.** `tailscaled --tun=userspace-networking
--socks5-server=127.0.0.1:1055`, `TS_AUTHKEY` présente dans l'environnement, DERP en HTTPS
vers `*.tailscale.com` (autorisé). Une fois le VPS sur le tailnet avec `tailscale up --ssh`,
**Tailscale SSH** répond (`SSH-2.0-Tailscale` sur le port 22 de l'IP 100.x, par le SOCKS5) :
le démon termine la connexion en espace utilisateur, sans dépendre du pare-feu ni du routage
de la cible. Client : `paramiko` depuis PyPI (`noProxy`) — il n'y a **ni `ssh` ni `sshpass`**
dans la VM. Pont réutilisable : `/home/user/.pxl/vps.py` (exec + SFTP).

Mesuré aussi, non élucidé : **le TCP brut par le tailnet vers ce VPS échoue sur tous les
ports** (`socks5: context deadline exceeded`), alors que `tailscale ping` répond en 130 ms,
que `tailscale0` y est montée en mode noyau, que `ts-input -i tailscale0 -j ACCEPT` existe et
que la table 52 porte les routes. Seul le chemin espace-utilisateur marche. Reste ouvert.

**Nuance au §4 et au §7 :** `add_repo` en lecture sur un dépôt public tiers
(`Ysurac/openmptcprouter-vps`, `BELABOX/srtla`) rend `read_available` : **le proxy git sert
les clones anonymes de dépôts publics**, sans rien attacher (`/home/user/<owner>/<repo>`).
Ce qui reste hors d'atteinte, c'est l'*attachement* (push, API). « Attacher est impossible »
(§7) est vrai ; « lire un dépôt tiers est impossible » ne l'est pas. Les pages GitHub
(`/wiki`, `raw.githubusercontent.com`) restent réécrites/403 : c'est le clone qui passe.

Autres mesures : `WebSearch` fonctionne ; `WebFetch` vers `arxiv.org` et `usenix.org` →
`EGRESS_BLOCKED`. `tailscale up` **réaffiche `TS_AUTHKEY` en clair** dans son message
d'aide quand on relance avec des flags différents — la clé finit dans le transcript.
Redémarrage du conteneur (nuit du 11 au 12/09) : workdir survivant (canari), mais **tous les
démons morts**, `run_in_background` compris — la différence avec `(cmd &)` est que la tâche
suivie **notifie** sa mort ; aucune des deux ne lui survit.

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

**Mesuré le 03/10/2026** (session TurboHQ, VM survivante) — deux faits de plus, à ajouter au tableau sans le
réécrire :

| Opération | Verdict |
|---|---|
| `push` vers une **autre** branche existante du dépôt (`HEAD:master`) | ✅ (avance rapide) |
| 🔴 `push` de **tags** (`refs/tags/archive/*`, 7 tags annotés) | ❌ **403** sur le POST `receive-pack`, comme la suppression |
| `git fetch --unshallow origin` | ✅ (2 s) |

> 🔴 **Le clone d'un dépôt de session peut être SUPERFICIEL.** Le 03/10, `PXL-TurboHQ` l'était
> (`git rev-parse --is-shallow-repository` → `true`, cinq limites dans `.git/shallow`, datées du 31/08
> au 10/09) ; `PXL-CC-over-AnthrVM`, dans la même VM, ne l'était pas. **Cause non mesurée** (profondeur
> de clone du harnais ? clone refait par une session précédente ?) — seul l'effet l'est : sur un clone
> superficiel, `git rev-list --max-parents=0` rend les **limites de troncature comme des racines**,
> `merge-base` rend « aucune base », `--is-ancestor` répond non à tort, et toute conclusion sur
> l'histoire est fausse sans qu'aucune commande n'échoue. Voir errata 11.
> ⇒ **Réflexe : `git rev-parse --is-shallow-repository` avant toute conclusion sur l'histoire d'un
> dépôt cloné par la session, et `git fetch --unshallow origin` s'il répond `true`.**

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

### 17/10/2026 — ⭐ du code WINDOWS compilé ET exécuté dans la VM (session TurboHQ, mesuré)

- **`apt-get install -y --no-install-recommends g++-mingw-w64-x86-64-posix wine64` passe** par le proxy, en ~1 min
  pour les deux (Ubuntu noble : GCC 13 mingw-w64, Wine 9.0).
- **mingw-w64 cross-compile un vrai DLL COM Windows et son banc console.** Le cas : `pxl-virtual-decklink` de
  PXL-TurboHQ, qui touche D3D11, COM et Win32. La commande : `x86_64-w64-mingw32-g++ -std=c++17 -shared … x.def -static
  -lole32 -loleaut32 -luuid -ld3d11 …`. Il a trouvé une vraie faute que MSVC masquait : `#include <memory>` manquant.
- **`wine64 banc.exe` l'exécute.** Réglages : `WINEPREFIX` dans le scratchpad, `WINEDEBUG=-all`, et
  `WINEDLLOVERRIDES="mscoree,mshtml="` (sinon Wine propose Mono et Gecko). Ce qui marche : mémoire partagée nommée,
  événements, fils, minuteur haute résolution (`CREATE_WAITABLE_TIMER_HIGH_RESOLUTION`), COM en processus.
- **Limites mesurées :**
  - aucune texture D3D11 partagée par handle NT : sans GPU, la création échoue ;
  - aucun plafond mémoire par objet job : `JOB_OBJECT_LIMIT_PROCESS_MEMORY` reste sans effet.
- **Méthode.** Le DLL d'AVANT les changements tourne dans le même Wine (la référence intercalée, §1) : 97/110 avant,
  109/129 après, avec les MÊMES 13 échecs d'environnement. Sans cette référence, ces échecs se seraient lus comme des
  régressions.
- **Une dépendance absente se remplace par un faux minimal, gardé dans le scratchpad.** Le cas : le `DeckLinkAPI64.dll`
  de Blackmagic, que le proxy exige.
- **Règle.** « On ne peut pas compiler ici » n'est plus vrai pour Windows : tenter mingw + Wine avant de livrer du C++
  Windows à l'aveugle. Ce qui touche le GPU reste pour le PC.
- **Supposé, non mesuré :** `qemu-user` s'installerait de la même façon. Cela toucherait la ligne « Exécuter du code
  ARM » du §7.
- **Ajout, 17/10 09:40 UTC — la méthode est versée au dépôt PXL-TurboHQ :** `pxl-virtual-decklink/wine/banc_wine.sh`.
  Une commande installe les outils, compile l'arbre de travail ET la référence (HEAD), pose le faux DeckLinkAPI dans
  le préfixe, lance les deux bancs et compare leurs échecs. Contre-épreuve : une faute injectée ressort seule, avec le
  code 1. ~1,5 min, préfixe Wine gardé.

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
| Joindre un hôte hors allowlist | 403 CONNECT (§3) |
| Localiser la VM | metadata bloquée (§1, §3) |
| **Autoriser un serveur MCP en OAuth** | le flux est interactif ; en session non-interactive c'est impossible. Vu le 01/08 sur le connecteur Canva. ⇒ passe par les réglages claude.ai de l'utilisateur |
| Plafonner la VRAM par un flag Chromium | §6 piège 4 |
| **Afficher un canvas WebGPU** (et donc tester un rendu à l'écran) | §6 piège 6 — présenter perd le device |
| **HEVC en WebCodecs** | §6 piège 7 — même le vrai Chrome ne l'embarque pas sous Linux |

> ⚠️ **17/10/2026 — réserve sur la ligne ARM ci-dessus (non mesurée).** `apt-get install` passe désormais par le
> proxy (mingw-w64 et Wine installés et exécutés ce jour-là, §5). `qemu-user` est donc probablement installable lui
> aussi : à mesurer avant de recopier « définitivement ».

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

6. ❌ **« Le VPS est bloqué par l'allowlist d'egress ; ajoutez-le et SSH passera. »** (11/09)
   Faux à moitié, et la moitié fausse aurait fait perdre une journée : le tunnel ne passe
   que du TLS/443, **SSH ne passe jamais**, allowlist ou pas. L'erreur venait de lire un
   `CONNECT 200` puis un silence comme « le proxy accepte, la cible ne répond pas ». Le
   témoin `github.com:80` — hôte autorisé, port ouvert, même symptôme — a renversé le
   diagnostic. **Leçon : avant d'accuser la cible, rejouer le test sur un témoin dont on
   connaît la réponse.** (§3 bis)

7. ❌ **« Pas de `debian13-x86_64.sh` dans le dépôt d'OMR ⇒ Trixie non supporté ⇒ Debian 12. »**
   (11/09, recommandation donnée à Eliott) Faux : tous les `debianNN-x86_64.sh` sont des
   **liens symboliques vers un seul script**, dont la porte d'entrée accepte `VERSION_ID`
   13 (`debian9-x86_64.sh:153`). **Leçon : la liste des fichiers n'est pas la logique ;
   lire la condition, pas l'arborescence.**

8. ❌ **« Le routage d'OMR (règle `from all lookup 52`) mange les SYN-ACK du tailnet. »**
   (11/09, écrit avant d'entrer sur la machine) Non observé : une fois dedans, la table 52
   contient les routes tailnet correctes, le pare-feu accepte `tailscale0`, l'interface est
   montée. Le mécanisme annoncé n'explique rien, et la cause reste inconnue. Deux sous-erreurs
   en route : « `tailscale0` absente » (liste tronquée par `head -20`) et « pas de MPTCP »
   (`sysctl -n` muet là où `/proc/sys/net/mptcp/enabled` dit 1). **Leçon : une panne non
   expliquée reste non expliquée ; publier un mécanisme qu'on n'a pas observé, c'est le
   même piège que l'erratum 1, avec plus de vocabulaire.**

9. ❌ **Mise à jour d'OMR paquet par paquet** (12/09) : `apt upgrade` a monté `xray` et
   `shadowsocks-go` mais pas `omr-vps-admin` (dépendances), et les deux nouveaux binaires ont
   refusé les configurations que l'ancien `omr-vps-admin` génère. Retour arrière depuis le
   cache apt, `apt-mark hold`. **Leçon : un système livré par un installeur monolithique se
   met à jour par cet installeur, ou pas du tout.** Et le `xray` rétrogradé est revenu
   `active` sans réécouter ses ports — non élucidé, sans objet si OMR est retiré.

10. ✅ **Erratum 8, suite : le TCP par le tailnet est élucidé** (12/09 soir). `tailscale debug
   netmap` rend le filtre de paquets reçu par le nœud : « utilisateurs → moi:8080,443 » et
   « moi → moi », rien d'autre. Un nœud tagué **sans règle ACL de sortie** ne peut initier aucun
   TCP vers un pair, et le refus est silencieux (filtre appliqué chez le pair). Tailscale SSH
   passe par sa propre section, `tailscale ping` ne traverse pas le filtre. **Leçon : avant
   de chercher un mécanisme chez la cible, lire le filtre que le tailnet donne au nœud —
   `tailscale debug netmap`, clé `PacketFilter`.** Deux jours d'hypothèses sur le routage
   d'OMR pour une règle ACL absente.

11. ❌ **« `master` de PXL-TurboHQ repart de zéro le 08/09 : trois racines « Consolidation ». »** (03/10,
   écrit dans la note de session du dépôt et dit à Eliott) Faux : le clone était **superficiel**, et
   `git rev-list --max-parents=0` rend les limites de troncature comme des racines. Après
   `git fetch --unshallow` : 879 commits, **une** racine, du 16/04. L'observation était juste (trois
   commits sans parent visible), la conclusion tirée trop vite — et trois erreurs en chaîne derrière
   elle : des branches crues contenues « seulement par contenu », 70 messages de commit crus perdus (des
   tags d'archive allaient être posés pour les sauver), un fichier « récupéré » qui n'avait été que
   renommé. Débusqué par un `git push` vers un dépôt jetable qui a refusé : « shallow update not
   allowed ». **Leçon : avant de raisonner sur une histoire git, vérifier qu'on la voit en entier —
   `git rev-parse --is-shallow-repository`.** (§4, mesure du 03/10)

12. ❌ **« `date -u -d "$(uptime -s)"` convertit l'heure locale de `uptime -s` en UTC. »** (écrit le 18/10 à
   10:35 UTC, démenti à 15:12 UTC) Faux : `-u` vaut pour TOUT le processus, l'ENTRÉE de `-d` est lue en UTC
   aussi — le résultat est l'heure locale ré-étiquetée « UTC », +2 h en CEST. Le piège a été écrit au moment
   même où la VM passait en heure française (77b605f, « converti explicitement »), et il touchait trois lignes
   de `vm_survey.sh` : le « boot » affiché, le canari, et surtout `BOOT`, le seuil du reflog qui décide « clone
   SURVIVANT / NEUF » — 2 h de trop, donc un clone frais de moins de 2 h aurait passé pour survivant. Tant que
   TZ était UTC, la ligne était juste par accident ; vu au premier réveil en heure française (le 8e
   redémarrage, §2). Correctif : `btime` de `/proc/stat`, une époque, sans fuseau. **Leçon : une conversion de
   fuseau se vérifie contre une époque (`@secondes`), jamais en relisant la sortie ; et changer TZ est une
   mesure à refaire pour tout ce qui lit `date` sans `@` ni `-u` des deux côtés.**

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
