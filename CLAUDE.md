# CLAUDE.md — PXL-CC-over-AnthrVM

> **26/10/2026 — version resserrée** : ce fichier part dans chaque requête. Le texte d'avant, intégral, est dans
> **`HISTORIQUE-CLAUDE.md`** (récits, citations, mécanismes) ; le détail mesuré est dans **`DOSSIER_VM.md`** (les §
> cités ici). 🔴 Ne pas regonfler : une leçon longue va au dossier, ici au plus une ligne qui y renvoie.

## Nature

Dépôt d'**exploration**, pas de base de code : ni build, ni application, ni tests. Le sujet est **la VM Claude Code**
elle-même : ce qu'elle est, ce qu'elle sait faire, ce qu'elle refuse. Livrable : `DOSSIER_VM.md` et les sondes de
`probes/`. ⚠️ Ce dépôt décrit peut-être l'environnement où tu tournes : ses contraintes s'appliquent à toi, maintenant.

**Réflexe de début de session** : `bash probes/vm_survey.sh --canary`. Canari présent ⇒ workdir survivant ; absent ⇒
VM neuve.

## Règle de rédaction (inhabituelle)

- **Une VM n'est pas l'autre** : silicium, ports du proxy et versions d'outils changent d'une session à l'autre.
  - Une divergence est un **fait nouveau** : la mesurer, la dater, l'**ajouter**. Jamais « mettre à jour ».
  - Ne jamais citer un chiffre d'ici comme la vérité de la session en cours : relancer la sonde.
- **Les errata (§ 8) ne se nettoient pas** : une erreur corrigée s'y ajoute.
- **Partout, on sépare mesuré / calculé / supposé** (⭐ porteur · ⚠️ réserve · 🔴 bloquant).
- **Seuls trois points restent non mesurés** : la localisation de la VM, la durée de recyclage selon la doc, et la
  seconde couche du refus GitHub.

## 💶 Coût et réveils (26/10)

- 🔴 **Tous les rappels sont ARRÊTÉS.** Eliott, le 26/10 : « on stoppe tous les rappels, pour les autres sessions aussi ».
  - Sont arrêtées : la veille MBX (`veille_mbx.sh`) et la tâche horaire « Veille MBX pxl-switcher »
    (`trig_0159YbNREcbguE14fUPSLQhF`, désactivée).
  - On **ne les réarme pas** sans nouvelle demande d'Eliott. Leur mode d'emploi est dans l'HISTORIQUE (« VEILLE MBX »).
- **Ouvrir la session sur le SEUL dépôt utile** : chaque dépôt attaché ajoute son `CLAUDE.md` à chaque requête.
- **Économiser le contexte** : sorties d'outils bornées, et pas de sous-agent pour une recherche courte.
- **Cache de prompt** : `promptCacheTtl: "1h"` dans `.claude/settings.json`. Sans lui, le cache retombe à 5 min dès
  qu'on puise dans les crédits.

## GitHub et survie du travail (§ 4)

- 🔴 **Créer un dépôt ou supprimer une branche rend 403** depuis une session cloud : il faut une action humaine ou un
  poste local. Pour « supprimer » une branche, pousser un commit qui la vide.
- ⭐ **`add_repo` en cours de session marche** (02/08, § 4 bis, errata 7).
  - ⚠️ L'invite système garde la liste du démarrage : appeler `list_repos` avant de déclarer un dépôt inatteignable.
  - Un clone à la fois (sinon HTTP 429), avec un délai généreux.
- 🔴 **Push = survie** : tout livrable est committé ET poussé dans le tour qui le produit.
  - Travail long ⇒ `run_in_background` (tâche suivie, elle maintient la VM en vie).
  - **Jamais** `nohup` ni un processus détaché : le recyclage le tue en vol.

## Réseau sortant (§ 3)

- **403, 407 ou échec TLS inexpliqué** : lancer `curl "$HTTPS_PROXY/__agentproxy/status"` avant de suspecter son code.
  - Jamais désactiver la vérification TLS, jamais retirer `HTTPS_PROXY`.
  - ⚠️ `recentRelayFailures` est resté vide sur des connexions pendues (§ 3 bis, errata 6) : vide ≠ pas d'échec.
- 🔴 **Le filtrage se fait par HÔTE** (mesuré le 19/08 ; le 02/08 il se faisait par port, 80/443/53).
  - Mécanisme : une passerelle TLS d'Anthropic lit le SNI et rend 403 `Host not in allowlist: …`.
    Témoins : `pypi.org` → 200, `example.com` → 403.
  - ⇒ Le repli DERP-sur-443 ne contourne plus rien.
  - Remède : ajouter `*.tailscale.com` (au minimum `controlplane.`, `derp*.`, `log.`) dans les **Network egress
    settings** de l'environnement. Un ajout fait depuis l'interface WEB s'applique en direct aux sessions vivantes
    (errata 12).
  - Cloudflare Tunnel ne passe pas (port 7844). Lui comme Tailscale montrent un plan de contrôle qui réussit avant
    d'échouer.
  - Errata 16 : ce fait est resté un mois dans une branche dont j'avais refusé la fusion sur un diff lu à l'envers.

## Le tunnel Tailscale (§ 3 ter)

- **VM neuve** : `bash tunnel_up.sh [port]`.
  - La clé de nœud ne se persiste pas : le workdir disparaît, et la versionner publierait un secret.
  - Ce qui survit, c'est **`TS_AUTHKEY`**, dans les variables de l'environnement (claude.ai/code → icône nuage
    au-dessus de la saisie → roue dentée ; il n'y a pas d'URL directe).
  - 🔴 Cette boîte n'est pas un coffre : ses valeurs sont lisibles par quiconque utilise l'environnement. Donc une clé
    **réutilisable + éphémère + taguée** (errata 8). `serve`, jamais `funnel`.
- **Variables d'environnement et conteneur** :
  - une variable ne prend effet qu'à la **naissance** d'une VM (03/08) ; rafraîchir en re-provisionne une, ce n'est
    pas une synchro ;
  - le conteneur, lui, persiste entre les invocations (`uptime` mesuré deux fois).
- 🔴 **L'ACL d'un nœud ne se teste pas depuis ce nœud** : proxy → 502, et `--accept-dns=false` ⇒ pas de MagicDNS.
  Un échec là n'est pas un refus d'ACL. Policy de référence : `tailscale-policy.hujson`.
- **Deux hooks, pour deux événements différents — il faut les deux** :
  - `SessionStart` → `session_start.sh` (la VM repart, il n'y a jamais eu de tunnel) :
    - console puis tunnel, idempotent, ~10 s à chaud, sort toujours en 0 ;
    - demande `TS_AUTHKEY` et `PXL_CONSOLE_MOTDEPASSE` dans l'environnement (sans le second, le mot de passe est tiré
      au sort à chaque réveil).
  - `PreToolUse` → `.claude/hooks/tunnel-vivant.mjs` (le tunnel meurt SOUS une session vivante : 3 fois le 09/09) :
    - ne sonde que les commandes qui visent la carte (`pxl-tx`, `100.94.64.107`, `tailscale nc`, `deployer-carte.sh`) ;
    - prédicat **`Self.Online`, jamais le code de retour** : `tailscale status` sort en 0 sur un nœud déconnecté
      (`tunnel_up.sh` l. 124-128) ;
    - ne bloque jamais ;
    - il supprime la méprise : `failed to connect to local tailscaled` puis
      `Connection closed by UNKNOWN port 65535` décrivent la VM, pas la carte ;
    - la seule preuve qu'il est armé : `tailscaled` tué, puis la proie donnée au hook ⇒ tunnel remonté en ~13 s.
- 🔴 **Ces hooks ne s'arment que si la session ouvre CE dépôt.** Une session sur le parent `/home/user` n'en lit aucun
  (30/08). Le 09/09, ils étaient tous inertes.
  - Premier geste d'une VM neuve :
    `mkdir -p /home/user/.claude && cp PXL-Switcher/.claude/settings-parent.json /home/user/.claude/settings.json`.
  - Contrôle : `ls /home/user/.claude/settings.json`. Un hook absent et un hook qui laisse passer se taisent pareil.
  - Le discriminant : donner sa proie au hook, il doit rendre `rc=2` :
    `printf '{"tool_name":"Bash","tool_input":{"command":"…"}}' | node .claude/hooks/pas-de-pkill-f.mjs`.
- 🔴 **L'entrant ne passe que si le relais HOME est celui des pairs** (03/08).
  - La VM est aux USA et choisit `nyc` ; un pair européen y envoie et rien n'arrive, alors que le sortant marche. Ça
    ressemble à une ACL, ce n'en est pas une.
  - `tunnel_up.sh` force la région la plus peuplée chez les pairs en ligne (`TS_DERP_REGION` pour surcharger) ;
    `force-prefer-derp` ne vaut que « until restart ».
- 🔴 **Le port du proxy de session change** quand l'infrastructure redémarre (signe : les MCP se déconnectent puis se
  reconnectent).
  - `tailscaled` avait mémorisé l'ancien ⇒ il perd sa sortie et meurt. Relancer la console **puis** `tunnel_up.sh`.
  - ⚠️ `tailscale ping` d'un pair vers la VM est soumis à l'ACL : avec une règle `:443` seule, il échoue même quand
    tout marche. Ne pas diagnostiquer avec.
- ⚠️ **Un nœud porte deux noms** : `HostName` (affiché) et `DNSName` (l'URL, figé à l'enregistrement).
  - Un suffixe `-1` marque une collision. Supprimer l'homonyme rend le `HostName`, pas le `DNSName`.
  - Pour reprendre le nom : `tailscale logout` puis `tunnel_up.sh`. Surtout pas un rafraîchissement de session, qui
    recrée la VM et tue la console.
  - Le nœud éphémère meurt avec la VM : relancer console puis tunnel à chaque réveil, dans cet ordre.

## La carte depuis la VM (§ 3 sexies)

- **Joignable depuis le 29/08** : la carte est taguée `tag:pxl-dev`, et une règle ouvre **22 · 8710 · 443 · 8443**.
  Ouvrir un port n'allume rien derrière : 443 et 8443 sont ouverts et vides.
- **`tailscale nc` est le SEUL outil qui route le 100.x** (userspace-networking : ni `curl` ni le proxy ne le voient).
  `~/.ssh/config` porte un hôte `pxl-tx` dont le `ProxyCommand` s'en sert.
- **Trois verdicts possibles** :
  - refusé (RST) = la bonne nouvelle : l'ACL passe, rien n'écoute ;
  - **pendu** = refus d'ACL, car Tailscale jette en silence ;
  - toujours sonder un port hors règle en contrôle, sinon les deux se confondent.
  - ⚠️ `timeout … | head` rend le code de `head` : un faux `rc=0`.
- **SSH** : `tailscale ssh radxa@100.94.64.107`.
  - Il faut les deux moitiés : `tailscale set --ssh` sur la carte, **et** un bloc `ssh` en **`accept`**,
    `src: tag:pxl-vm` → `dst: tag:pxl-dev`. Jamais `check` : il demande une ré-authentification humaine dans un
    navigateur.
  - « host key verification failed » ⇒ Tailscale SSH n'est pas actif sur la carte.
  - « tailnet policy does not permit… » ⇒ il l'est, et c'est la policy qui manque.
- **Piloter le desk sans sortir le mot de passe** : tout s'exécute SUR la carte (`ssh … 'bash -s' <<'FIN'`), et `curl`
  parle à `127.0.0.1:8710`. Pièges silencieux :
  - `set -a` avant de sourcer `/etc/default/pxl-console` ;
  - mot de passe par STDIN (`curl --data @-`), jamais en argv ;
  - enveloppe `{"command":…,"args":{}}` ;
  - 🔴 l'état est sous `s.state.compositions` : lire `s.compositions || {}` rend « desk vide » avant ET après.
  - Desk en service : empreinte des deux compositions avant et après. Un `ok:true` sans changement est indiscernable
    d'une commande qui a marché.

## Outils de la VM

- **Chromium** :
  - contexte sécurisé obligatoire (`http://127.0.0.1:<port>`, pas `about:blank`) ;
  - il hérite de `HTTPS_PROXY` ⇒ `proxy: {server: 'direct://'}` ;
  - binaire `/opt/pw-browsers/chromium` (lien symbolique, ne pas versionner la révision) ;
  - ne pas lancer `playwright install`.
- **ARM** : `clang --target=aarch64-linux-gnu` compile sans chaîne croisée, mais il n'y a pas de `qemu-user` ⇒ rien
  d'ARM ne s'exécute. La correction se prouve, l'exactitude non.
- **Perf** : aucune mesure n'est comparable d'une session à l'autre (le CPU change). Seuls les rapports le sont, avec
  une référence réintercalée dans la même VM.

## Documents liés

`PXL-StageBox/jpegxs-arm/README.md` : la méthode de la référence intercalée, justifiée a posteriori par le § 1 d'ici ·
`PXL-Tape` : le dépôt d'origine des notes.
