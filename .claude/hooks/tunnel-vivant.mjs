#!/usr/bin/env node
// ─────────────────────────────────────────────────────────────────────────────
// LE TUNNEL EST-IL VIVANT AVANT QU'ON PARLE À LA CARTE ?
// PreToolUse sur Bash. Demandé par Eliott le 09/09/2026 : « tu devrais te faire
// un hook pour verif tailscale quand la VM repart ».
//
// ─── Pourquoi ce hook-ci, et pas seulement `session_start.sh` ────────────────
//
// `session_start.sh` couvre le réveil de la VM (hook SessionStart) et il le fait
// bien. Il ne couvre PAS ce qui a mordu trois fois dans la seule séance du
// 09/09 : le tunnel tombe **en cours de session**, sans que rien ne redémarre.
// Un SessionStart n'aurait attrapé aucune des trois. Les deux sont donc
// nécessaires et ne visent pas le même événement :
//
//   SessionStart  → la VM repart, il n'y a jamais eu de tunnel   (session_start.sh)
//   PreToolUse    → le tunnel est mort SOUS une session vivante  (ce fichier)
//
// ⚠️ La cause connue du second cas est écrite dans DOSSIER_VM.md § 3 ter : le
// port du proxy de sortie de la session change quand l'infrastructure redémarre,
// `tailscaled` l'a mémorisé à son démarrage, il perd sa sortie et MEURT. Rien
// dans la session ne le signale — le seul témoin est un `ssh` qui rend
// « failed to connect to local tailscaled » puis « Connection closed by UNKNOWN
// port 65535 », c'est-à-dire un message qui décrit la VM et se lit comme une
// panne de la CARTE. C'est ça qu'on supprime : pas la panne, la MÉPRISE.
//
// ─── Le prédicat, et pourquoi ce n'est pas le code de retour ─────────────────
//
// 🔴 `tailscale status` SORT EN 0 SUR UN NŒUD DÉCONNECTÉ — mesuré le 05/09, et
// c'est écrit en toutes lettres dans `tunnel_up.sh` (l. 124-128) : le démon sert
// alors sa dernière carte du réseau, les pairs s'affichent tous `active`, et une
// garde naïve annonce « tout va bien » exactement quand ça ne va pas. Le seul
// fait qui tranche est **`Self.Online`** dans le JSON. On lit donc le même
// prédicat que le script qu'on appelle — deux prédicats pour la même question
// seraient le énième « deux modèles ».
//
// ─── Trois règles de conduite, les mêmes que les autres hooks du dépôt ───────
//
//  1. **IL NE BLOQUE JAMAIS** — sortie 0 dans tous les cas, y compris quand la
//     remontée échoue. La doctrine du dépôt est qu'un hook d'observation qui
//     casse le travail est retiré dans la semaine. Quand la remontée échoue on
//     le DIT fort, et la commande part quand même : elle échouera une seconde
//     plus tard, avec l'explication juste au-dessus dans le transcript.
//  2. **Il se tait quand tout va bien.** Le témoin d'un hook qui marche est le
//     silence — donc rien n'est imprimé sur un tunnel vivant. ⚠️ Corollaire
//     connu (MISTAKE.md § 13) : un hook NON CHARGÉ et un hook qui laisse passer
//     sont indiscernables. Le discriminant coûte une commande — lui DONNER sa
//     proie :
//       printf '{"tool_name":"Bash","tool_input":{"command":"ssh pxl-tx true"}}' \
//         | node .claude/hooks/tunnel-vivant.mjs
//     doit imprimer une ligne de vérification (ou rien, si le tunnel est vivant
//     — auquel cas couper `tailscaled` d'abord pour le voir travailler).
//  3. **Il est borné.** Le sondage a un timeout court, la remontée un timeout
//     long mais fini. Aucun chemin ne peut suspendre la session.
//
// ─── Ce qu'il ne fait PAS, et c'est délibéré ─────────────────────────────────
//
// Il ne sonde que les commandes qui VISENT LA CARTE. Sonder tous les `Bash`
// paierait un `tailscale status` sur chaque `ls`, et surtout il remonterait un
// tunnel dont on n'a pas besoin — un effet de bord au moment où on ne le
// demande pas. La liste des motifs est étroite exprès.
//
// 🔒 Il n'imprime JAMAIS `TS_AUTHKEY` ni aucune valeur d'environnement : il ne
// fait que les transmettre à `tunnel_up.sh`, qui en a besoin. Rien ici ne lit
// une variable sensible pour l'afficher.
// ─────────────────────────────────────────────────────────────────────────────

import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

// Un hook qui plante laisse passer : tout le corps est sous un seul filet.
try {
  main();
} catch {
  // Volontairement muet. Une erreur de CE fichier ne doit pas colorer le
  // diagnostic d'une commande qui n'a rien à voir.
}
process.exit(0);

function main() {
  const brut = lireEntree();
  if (!brut) return;

  let charge;
  try { charge = JSON.parse(brut); } catch { return; }
  if (charge?.tool_name !== 'Bash') return;

  const cmd = String(charge?.tool_input?.command ?? '');
  if (!cmd) return;

  // ── Ce hook ne concerne que ce qui part VERS LA CARTE. ─────────────────────
  // `pxl-tx` est l'hôte de ~/.ssh/config, `100.94.64.107` son adresse tailnet,
  // `tailscale nc` le seul outil qui route le 100.x (userspace-networking).
  const VISE_LA_CARTE = /\bpxl-tx\b|100\.94\.64\.107|tailscale\s+nc\b|deployer-carte\.sh/;
  if (!VISE_LA_CARTE.test(cmd)) return;

  // ⚠️ On ne se sonde pas soi-même : `tunnel_up.sh` sait déjà tout faire, et
  // remonter juste avant de le lancer ne serait qu'un doublon coûteux.
  if (/tunnel_up\.sh/.test(cmd)) return;

  const racine = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
  const tsDir = process.env.TS_DIR || join(racine, '.tailscale');
  const bin = join(tsDir, 'tailscale');
  const sock = join(tsDir, 'ts.sock');
  const script = join(racine, 'tunnel_up.sh');

  if (!existsSync(script)) return;   // pas ce dépôt-ci : on n'a rien à dire.

  if (enLigne(bin, sock)) return;    // ⭐ tout va bien ⇒ SILENCE.

  console.log('[tunnel] Self.Online est faux — remontée avant de parler à la carte…');
  const ok = remonter(script, racine, tsDir);

  if (ok && enLigne(bin, sock)) {
    console.log('[tunnel] ✅ remonté, la commande peut partir.');
  } else {
    // 🔴 On NE BLOQUE PAS (règle 1). On nomme la cause, fort, pour que l'échec
    // qui suit ne soit pas imputé à la carte — c'est toute la valeur du hook.
    console.log('[tunnel] 🔴 REMONTÉE ÉCHOUÉE — la commande va partir et échouer.');
    console.log('[tunnel]    La panne est ICI (la VM), pas sur la carte.');
    console.log('[tunnel]    À la main : cd PXL-CC-over-AnthrVM && bash tunnel_up.sh');
    console.log('[tunnel]    Si ça résiste : TS_AUTHKEY est-il posé dans les variables');
    console.log('[tunnel]    d\'environnement de l\'environnement Claude Code ? (clé');
    console.log('[tunnel]    réutilisable + éphémère + taguée, expire à 90 jours)');
  }
}

// ⚠️ Le JSON arrive sur stdin. `readFileSync(0)` bloquerait si personne
// n'écrit ; en PreToolUse il y a toujours une charge, et le filet du haut
// couvre le cas contraire.
function lireEntree() {
  try { return readFileSync(0, 'utf8'); } catch { return ''; }
}

// 🔴 `Self.Online`, JAMAIS le code de retour — voir l'en-tête.
function enLigne(bin, sock) {
  if (!existsSync(bin) || !existsSync(sock)) return false;
  try {
    const out = execFileSync(bin, [`--socket=${sock}`, 'status', '--json', '--peers=false'],
      { encoding: 'utf8', timeout: 5000, stdio: ['ignore', 'pipe', 'ignore'] });
    return JSON.parse(out)?.Self?.Online === true;
  } catch {
    return false;
  }
}

function remonter(script, racine, tsDir) {
  try {
    execFileSync('bash', [script], {
      cwd: racine,
      env: { ...process.env, TS_DIR: tsDir },
      timeout: 180000,
      stdio: ['ignore', 'ignore', 'ignore'],
    });
    return true;
  } catch {
    return false;
  }
}
