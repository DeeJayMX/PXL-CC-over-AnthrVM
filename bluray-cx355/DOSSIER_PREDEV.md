# BD-355 — Dossier de pré-développement

**Jukebox Blu-Ray 300 disques sur base Sony CDP-CX355, géré par serveur web, streamé sur téléphone.**

> Avoir *ses* films, vraiment partout — sans abonnement, sans catalogue qui rétrécit, avec les
> disques qu'on possède physiquement, rangés dans un carrousel qui les sert tout seul.

Convention héritée du dépôt : chaque affirmation est marquée **mesuré** / **calculé** /
**supposé**. À ce stade de pré-dev, *rien n'est encore mesuré sur le matériel réel* — les faits
« sûrs » sont des specs publiques, tout le reste est supposé et fléché vers un test d'établi
(§7). ⭐ fait porteur · ⚠️ réserve · 🔴 bloquant potentiel.

---

## 0. La vision en une phrase

Le téléphone affiche la jaquette des 300 films du carrousel ; on en touche une ; le CX355
tourne, charge le disque dans un bloc de lecture Blu-Ray greffé à la place du bloc CD ; le
serveur lit, transcode et streame ; l'image arrive sur le téléphone en moins d'une minute —
chez soi ou à l'autre bout du monde.

---

## 1. Le donneur : ce que le CDP-CX355 est — et n'est pas

Le CDP-CX355 (Sony « MegaStorage », fin des années 90) est un changeur **300 CD** :

| Ce qu'on garde | Ce qu'on jette |
|---|---|
| ⭐ Le carrousel 300 slots et sa rotation motorisée | Le bloc optique CD (KSS-2xx, laser 780 nm) |
| ⭐ L'ascenseur/chargeur qui extrait un disque de son slot et le pose sur le plateau de lecture | La carte de traitement audio CD (DAC, servo CD) |
| Les capteurs de position d'origine (fin de course, indexation slot) — *supposé exploitables* | Probablement la carte mère de commande d'origine (§5) |
| Le châssis, la façade (esthétique du produit fini) | |
| ⚠️ Éventuellement le bus Control-A1II (mini-jack 3,5 mm) comme voie de commande | |

**Compatibilité physique des disques** (specs publiques, ⭐) : un Blu-Ray a exactement le même
format qu'un CD — 120 mm, 1,2 mm d'épaisseur, ~16 g, trou central 15 mm. Le carrousel stocke
donc 300 BD sans aucune modification. Bonus : le revêtement dur des BD (Durabis) les rend
*moins* fragiles à la manipulation robotisée que les CD.

**État mécanique attendu** (supposé, bien documenté chez les collectionneurs) : ⚠️ les
MegaStorage de cet âge ont presque toujours des **courroies de chargement fatiguées**. Un kit
de courroies neuves fait partie de la BOM d'office, avant tout diagnostic.

---

## 2. Verdict optique : pourquoi on ne « modifie » pas la lentille

Pour tuer l'idée séduisante une bonne fois (specs publiques, ⭐) :

| | CD | Blu-Ray |
|---|---|---|
| Laser | 780 nm (infrarouge) | 405 nm (violet) |
| Ouverture numérique | 0,45 | 0,85 |
| Couche de protection | 1,1 mm | 0,1 mm |
| Débit 1× | 1,4 Mbit/s | 36 Mbit/s |

Rien n'est réutilisable dans le bloc optique : ni le laser, ni la lentille, ni le servo, ni
l'électronique de lecture. **La seule voie est la greffe d'un lecteur Blu-Ray complet** (bloc
optique + servo + contrôleur SATA/USB, indissociables) à la station de lecture. Ce n'est pas
une mauvaise nouvelle : un lecteur BD de PC coûte 60–90 €, sait lire à 6–12× (largement au-delà
des 48 Mbit/s max d'un film), et sort les données en USB/SATA — exactement ce qu'un serveur
veut.

---

## 3. Architectures candidates

### Option A — la greffe : un lecteur BD « mis à nu » à la station de lecture *(la cible)*

Démonter un lecteur BD (slim 9,5 mm de portable, ou demi-hauteur de bureau), retirer son
tiroir/capot, et monter son mécanisme (moteur de broche + chariot + bloc optique + carte)
à l'emplacement exact du plateau CD d'origine, pour que **l'ascenseur du CX355 pose le disque
directement sur la broche du lecteur BD**.

- ⭐ Réutilise le geste mécanique que le CX355 sait déjà faire — aucun bras à inventer.
- 🔴 Risque n°1 : la géométrie (hauteur de broche, débattement du clamp magnétique, zone de
  dégagement du chariot optique). À mesurer avant tout achat définitif (test T2, §7).
- 🔴 Risque n°2 : le firmware du lecteur BD attend *son* cycle de chargement (capteurs tiroir /
  slot-in). Il faudra leurrer ses fins de course pour lui faire croire qu'il a chargé lui-même
  (test T3). Les lecteurs à tiroir sont supposés plus simples à leurrer que les slot-in
  (capteurs discrets vs rouleaux entraînés).
- Choix du lecteur : privilégier un modèle flashable **LibreDrive** (famille LG WH16NS40 /
  BU40N slim) — lecture sans entrave des BD et UHD via MakeMKV, très documenté.
- ⭐ **2026-08-20 — le format se tranche à la mécanique du moyeu, pas à l'encombrement** :
  voir l'annexe A. Le demi-hauteur (disque *posé* + palet magnétique) reproduit le geste du
  CX355 ; le slim (moyeu à clips, pression au clic / arrachage) exigerait un presseur et un
  décolleur en plus. Le demi-hauteur devient la voie de référence, le slim un repli de T2.

### Option B — le bras de transfert : lecteur slot-in externe intact

Le CX355 amène le disque en position, un bras de transfert à concevoir (pince + 2 axes) le
porte jusqu'à la fente d'un lecteur slot-in resté intact.

- Découple totalement la géométrie du lecteur de celle du changeur ; le lecteur reste stock.
- ⚠️ Mais on introduit toute la mécanique que l'option A évite : préhension d'un disque par la
  tranche, alignement avec une fente, gestion des ratés. C'est un deuxième robot dans le robot.
- À garder comme **plan de repli** si T2 révèle une géométrie impossible.

### Option C — la bibliothèque : rip intégral, le carrousel devient archive froide *(fast-track)*

Sans toucher au CX355 : ripper les 300 disques une fois pour toutes sur un simple PC + lecteur
BD, servir le tout via Jellyfin. Le CX355 garde les originaux — preuve de possession et
esthétique.

- ⭐ Livre « ses films partout » en quelques semaines, zéro risque mécanique.
- Calculé : 300 disques × ~30 Go (film principal en MKV) ≈ **9 To** → un disque 12–14 To
  suffit. En version transcodée 1080p (~8 Go/film) : 2,4 To.
- ⚠️ Perd le geste jukebox — le disque physique qui se charge — qui est l'âme du projet.

**Recommandation : C et A en parallèle.** C est le filet de sécurité qui rend service dès le
premier mois et fournit l'infrastructure logicielle (serveur, inventaire, streaming) que A
réutilisera à l'identique. A est le vrai projet. Et une fois A opérationnel, le jukebox peut
*lui-même* alimenter C : rip automatique du carrousel pendant la nuit, disque par disque.

---

## 4. Chaîne logicielle

```
téléphone (PWA / app Jellyfin)
        │  HTTPS (LAN ou WAN via reverse-proxy + auth)
        ▼
serveur web  ──────────────  base d'inventaire (slot ↔ disque ↔ fiche TMDB)
        │ commande                    ▲ identification
        ▼                            │
contrôleur changeur (§5)      lecteur BD greffé
  sélection slot → chargement ──► lecture (makemkvcon : déchiffrement + flux MKV)
                                     │
                                     ▼
                              ffmpeg (transcode matériel → HLS/DASH)
                                     │
                                     ▼
                              téléphone : lecture
```

**Deux modes de service :**

- **Jukebox (streaming direct du disque)** — le disque est lu à la demande.
  `makemkvcon` sait exposer un titre en flux pendant la lecture du disque ; ffmpeg le
  transcode à la volée. Latence bouton→image estimée (calculé, à mesurer en T6) :
  rotation carrousel (2–8 s) + chargement (~5 s) + spin-up et authentification AACS
  (15–40 s) ≈ **30–60 s**. C'est le prix du geste ; l'UI doit l'assumer (animation du
  carrousel en train de tourner plutôt qu'un spinner générique).
- **Bibliothèque (cache)** — tout titre déjà ripé (mode C ou rip nocturne) part
  instantanément via Jellyfin. Le jukebox ne se déclenche que pour les titres pas encore
  en cache. À terme, le mode jukebox devient le mode d'ingestion.

**Identification des disques** : à chaque premier chargement d'un slot, empreinte du disque
(identifiant de volume/du disque remonté par makemkvcon), rapprochement TMDB pour titre +
jaquette, écriture dans l'inventaire. Un « scan du carrousel » nocturne construit tout seul le
catalogue des 300 slots.

**Transcodage — le piège Raspberry Pi** ⚠️ : le Pi 5 n'a **pas d'encodeur vidéo matériel**
(décodage HEVC seulement). Transcoder du BD 1080p en logiciel sur Pi = intenable. Le serveur
sera un **mini-PC x86 Intel N100** (~150 €) : QuickSync encode H.264/HEVC/AV1 sans effort,
plusieurs flux simultanés, et le lecteur BD greffé s'y branche en USB/SATA directement.

**Accès distant** : reverse-proxy + TLS + auth forte (ou VPN Wireguard/Tailscale, plus simple
et plus sûr pour un usage personnel). Un seul utilisateur simultané suffit au cahier des
charges — c'est *son* carrousel.

---

## 5. Pilotage du changeur : Control-A1II ou bypass ?

Deux voies, à départager sur établi (test T1) :

- **Voie douce — Control-A1II** : le bus Sony (mini-jack, protocole série lent partiellement
  documenté par la communauté) permet d'envoyer « sélectionne le disque N, play ». ⚠️ Réserve
  majeure (supposé) : une fois le bloc CD retiré, la carte mère d'origine ne verra jamais une
  lecture réussie — elle risque de décharger le disque ou de partir en erreur. La voie douce
  ne survivra probablement pas à la greffe.
- **Voie directe — bypass de la carte mère** : piloter directement les deux moteurs (rotation
  carrousel, ascenseur/chargeur) avec des drivers modernes (TB6612/DRV8871) et relire les
  capteurs de position d'origine, depuis un microcontrôleur (ESP32 ou RP2040) parlant série/USB
  au serveur. Le service manual du CX355 (schémas, nomenclature capteurs) circule et rend ça
  réaliste. **C'est la voie de référence du projet** ; Control-A1II reste utile en phase
  d'autopsie pour faire fonctionner la mécanique d'origine et l'observer.

Machine à états cible du contrôleur : `IDLE → SEEK(slot) → LOAD → SPIN(main BD) → UNLOAD →
RETURN` — avec détection de bourrage (timeout sur capteurs) et **inventaire persistant du slot
sorti** (un disque en cours de lecture n'est plus dans le carrousel ; une coupure de courant ne
doit pas perdre cette information).

---

## 6. Les chiffres qui dimensionnent (calculés, à re-vérifier)

| Grandeur | Valeur | Conséquence |
|---|---|---|
| Débit max d'un film BD | 48 Mbit/s | Un lecteur 2× (72 Mbit/s) suffit ; tous font ≥ 6× |
| Film BD complet | 25–45 Go | Rip intégral des 300 : ~9–12 To |
| Transcodé 1080p H.264 8 Mbit/s | ~8 Go/film | Cache complet : 2,4 To — tient sur un SSD |
| Latence jukebox | 30–60 s | UX à concevoir autour, pas à cacher |
| Flux distant 1080p | 8–12 Mbit/s | Passe sur la fibre montante ; 720p (4 Mbit/s) en 4G |

---

## 7. Ce qui doit être mesuré avant d'engager le fer

L'ordre est celui du risque : chaque test peut invalider la suite, aucun n'exige que le
précédent matériel soit détruit.

| # | Test d'établi | Ce qu'il tranche |
|---|---|---|
| T1 | CX355 stock : cycle complet de chargement observé (courroies neuves) ; comportement quand le disque est illisible (un BD, justement) | La mécanique survit-elle ? Décharge-t-il de lui-même un disque « NO DISC » ? → viabilité voie douce vs bypass |
| T2 | Relevé géométrique de la station de lecture (hauteur broche, course clamp, encombrement) vs cotes d'un lecteur BD slim et demi-hauteur démontés | **Go/no-go de l'option A**, choix slim vs demi-hauteur |
| T3 | Lecteur BD nu sur établi : leurrage des capteurs de chargement, disque posé à la main sur la broche → lecture ? | Le firmware accepte-t-il une insertion « divine » ? |
| T4 | Pilotage direct moteurs + capteurs du CX355 (carte mère débranchée) : 100 cycles slot aléatoire sans erreur | Fiabilité du bypass |
| T5 | `makemkvcon` en mode flux + ffmpeg QuickSync sur N100 : un BD du commerce → HLS lu sur téléphone | Toute la chaîne logicielle, sans le changeur |
| T6 | Bout-en-bout : bouton sur PWA → image, chronométré ×20 | La latence réelle, pour dimensionner l'UX |

T5 est **indépendant du CX355** : c'est par lui qu'on commence (c'est aussi le socle de
l'option C).

---

## 8. Cadre légal ⚠️ (réserve, non juriste)

Les Blu-Ray sont chiffrés (AACS). Les lire hors lecteurs agréés passe par MakeMKV/libaacs,
c'est-à-dire par le contournement d'une mesure technique de protection. En France (DADVSI),
ce contournement est en principe interdit et **l'exception de copie privée ne le neutralise
pas** — même pour ses propres disques, même sans diffusion. Le projet reste strictement
personnel (ses disques, son serveur, son téléphone, un utilisateur), ce qui borne le risque
pratique, mais le point doit être connu et assumé avant d'y investir. À documenter séparément
si le projet devient public.

---

## 9. Roadmap

| Phase | Contenu | Livrable |
|---|---|---|
| P0 | Fast-track option C : N100 + lecteur BD, chaîne T5, Jellyfin | Ses films sur son téléphone (sans jukebox) |
| P1 | Acquisition CX355 + courroies + service manual ; autopsie ; T1, T2 | Go/no-go option A, relevés cotés |
| P2 | Bypass moteur/capteurs ; T4 | Sélection de slot fiable, commandée en USB |
| P3 | Greffe du lecteur BD ; T3 puis intégration | Un disque choisi par logiciel est *lu* |
| P4 | Intégration chaîne P0 + changeur ; T6 | Bouton → image |
| P5 | Serveur final : inventaire auto des 300 slots, rip nocturne, accès distant, UI jaquettes | Le produit |

## 10. BOM indicative (~500–700 € hors stockage)

CDP-CX355 d'occasion (50–150 €) · kit courroies (15 €) · lecteur BD LibreDrive : BU40N slim
*et* WH16NS40 demi-hauteur pour trancher T2 (2 × ~80 €) · mini-PC N100 16 Go (150 €) · ESP32 +
drivers moteur + petites fournitures (30 €) · alim labo pour l'établi (déjà possédée ou 60 €) ·
licence MakeMKV (~60 €, la bêta gratuite suffit pour T3/T5) · SSD cache 4 To ou HDD 12 To selon
mode (180–250 €).

---

## Annexe A — Mécanique d'un lecteur : pourquoi le demi-hauteur gagne « par le haut »

*(ajouté le 2026-08-20, en réponse à « un lecteur style laptop, ouverture par le haut ? »)*

Deux familles de lecteurs, deux façons opposées d'accrocher le disque à la broche :

```
SLIM (laptop, 9,5/12,7 mm)              DEMI-HAUTEUR (bureau, 5"1/4)
tout le mécanisme est SUR le tiroir     mécanisme au fond du boîtier
(broche, laser, chariot sortent avec)   disque POSÉ librement sur la broche

   moyeu à clips (billes à ressort)        palet magnétique logé dans le capot
        ┌─── clic ! ───┐                        ▼ posé sur le disque
   disque PRESSÉ (~10 N) au chargement     disque tenu par attraction avec
   disque ARRACHÉ au déchargement          l'aimant de la broche — gravité + aimant
```

- **Slim** : fonctionne très bien « à nu », tiroir ouvert — mais le moyeu à clips exige une
  *pression au clic* pour charger et un *arrachage* pour décharger. L'ascenseur du CX355 sait
  poser et reprendre, pas presser ni arracher : il faudrait ajouter un presseur motorisé **et**
  un décolleur. Deux mécanismes de plus, deux sources de bourrage.
- **Demi-hauteur** : le disque *repose* sur la broche, le palet magnétique le plaque depuis le
  dessus. **C'est exactement le geste que le CX355 fait déjà** avec son propre clamp sur sa
  broche CD. La greffe se réduit à un problème d'alignement et de cotes (T2), pas de mécanisme.

**Recette de mise à nu d'un demi-hauteur à tiroir** (c'est le mode opératoire de T3) :

1. Capot retiré ; **conserver le palet magnétique** (réutilisé tel quel, ou remplacé par le
   clamp d'origine du CX355 si les cotes s'y prêtent — à trancher en T2).
2. Fermer le tiroir actionne une **glissière-came** qui soulève le mécanisme en position de
   lecture ; tiroir retiré, **bloquer cette came en « fermé »** — la broche reste haute en
   permanence.
3. **Ponter le microswitch « tiroir fermé »** : le lecteur se croit fermé pour toujours.
4. Disque posé main + palet + SATA/USB → `makemkvcon info disc:0` doit voir le BD.
5. ⚠️ Seul vrai inconnu du leurrage : beaucoup de firmwares ne re-détectent un *nouveau*
   disque qu'au cycle tiroir. Le déclencher en logiciel (`eject -t /dev/sr0` / commande ATA
   start-stop) — le moteur de tiroir brassera du vide, sans conséquence. À valider en T3.

Réserves d'intégration (supposé) : **poussière** (lecteur décapoté dans un châssis de
changeur ⇒ prévoir un carter léger) et **vibrations** (brider la vitesse de lecture par
commande ; 2× = 72 Mbit/s suffit à tout film).

---

*Pré-dev rédigé le 2026-08-20. Prochain geste : P0/T5 — la chaîne logicielle se valide sans
toucher un tournevis.*
