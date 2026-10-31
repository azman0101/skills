---
name: agent-rc-profile
description: Créer, vérifier et piloter des profils `agent-rc` (Claude Code lancé en arrière-plan dans tmux, avec Remote Control, caffeinate, sandbox macOS sandbox-exec et TokenEconomizer). À utiliser dès que l'utilisateur parle d'agent-rc, d'un profil agent, de ~/.config/agent-profiles, de lancer un agent Claude "en fond" ou "sandboxé" sur un dépôt, de session tmux claude-rc-*, de Remote Control persistant, ou veut ajouter un nouveau projet/dépôt à ce dispositif, même sans citer agent-rc.
---

# agent-rc : profils et utilisation

`agent-rc [profil] [action]` (`~/.local/bin/agent-rc`, zsh) lit `~/.config/agent-profiles/<profil>.env`
puis lance l'agent dans une session tmux détachée, sous `caffeinate` et `sandbox-exec`.
Un **profil = un dépôt = une session tmux**. Créer un profil, c'est écrire ce `.env`.

## Créer un profil

1. Vérifier que le dispositif existe : `test -x ~/.local/bin/agent-rc`, `command -v tmux`.
   S'il manque, proposer de l'installer depuis `<skill>/scripts/agent-rc` :
   `install -m 755 <skill>/scripts/agent-rc ~/.local/bin/agent-rc` (avec l'accord de l'utilisateur).
2. Rassembler les informations. Ne demander que ce qui ne se déduit pas :
   - **dépôt** (obligatoire) : le dossier de travail de l'agent ;
   - **secrets** : noms de variables et entrées Keychain (jamais les valeurs). Si l'utilisateur a
     d'autres secrets que l'agent ne doit pas pouvoir lire (ex: un autre fournisseur), proposer un
     **coffre dédié** (`--vault`, voir plus bas) ; sinon les secrets restent dans le trousseau de
     connexion, qui est lisible par l'agent ;
   - **télémétrie OTLP** : optionnelle, désactivée par défaut. N'en proposer aucun endpoint :
     l'utilisateur fournit le sien s'il a un collecteur (et dit si les prompts sont journalisés) ;
   - **outils et caches** : la sandbox n'autorise l'écriture que pour Rust par défaut. Identifier
     les outils du projet (kubectl, helm, aws, npm, uv, go…) et proposer `--write-path` pour leurs
     seuls dossiers de cache, jamais pour un dossier d'identifiants entier ;
   - **micro-skills TokenEconomizer** : désactivés par défaut dans TokenEconomizer, ce skill les
     active en `envfacts` (apprentissage sans appel de modèle). Le mode `on` ajoute un modèle qui
     propose des faits toutes les 3 sessions, **coût imputé à la session** : ne le choisir que si
     l'utilisateur le demande, en le lui signalant ;
   - **reprise** : conversation précise (UUID), la plus récente, ou `--continue` par défaut.
3. Générer avec le script (toujours `--dry-run` d'abord si l'utilisateur hésite) :

```bash
bash <skill>/scripts/new-profile.sh <nom> --project-dir <dépôt> \
  [--secret VAR=SERVICE[:COMPTE]]... [--otlp URL [--log-prompts]] \
  [--vault NOM] [--protect-keychain NOM]... [--write-path CHEMIN]... [--microskills envfacts|on|off|skip] [--resume UUID | --resume-latest] [--session N] [--rc-name N] [--agent-cmd C] [--force]
```

   Il valide les entrées, résout les liens symboliques du dépôt, signale les collisions de
   session/dépôt avec d'autres profils, vérifie la présence des entrées Keychain sans lire leur
   valeur, et écrit le fichier en `chmod 600`. Il n'écrase rien sans `--force`. Il exécute aussi
   `te config set microskills=<mode>` dans le dépôt (réglage stocké dans `~/.tokeneconomizer`, pas
   dans le `.env`, par dépôt) ; sans `te` installé, il affiche la commande à lancer.
4. Si une entrée Keychain manque, **ne pas** demander le secret dans le chat. Donner la commande
   `security add-generic-password -s SERVICE -a COMPTE -w` à lancer par l'utilisateur (saisie masquée).
5. Lancer `agent-rc <nom>`, puis confirmer avec `tmux has-session -t <session>`.

### Coffre dédié (secrets que l'agent ne doit pas lire)

La sandbox ne filtre pas le Keychain par nom de secret, mais elle peut interdire la lecture du
**fichier** d'un trousseau précis : `security` ne peut alors plus l'interroger, même déverrouillé,
ni lister ses noms. Le trousseau de connexion ne peut pas être protégé ainsi (Claude Code y stocke
ses identifiants). Le principe : les secrets à protéger vivent dans un trousseau dédié, hors de la
liste de recherche, dont le fichier est refusé à l'agent.

1. `scripts/vault.sh init` : crée le coffre `~/Library/Keychains/agent-vault.keychain-db`
   (mot de passe demandé, verrouillage auto 5 min). `scripts/vault.sh add SERVICE [COMPTE]` y
   ajoute chaque secret (valeur demandée sans écho). **Ces commandes sont interactives : les faire
   lancer par l'utilisateur**, ne jamais demander un mot de passe ou un secret dans le chat.
2. Créer le profil avec `--vault agent-vault --secret VAR=SERVICE[:COMPTE]`. `agent-rc` demande le
   mot de passe du coffre à chaque démarrage, charge les secrets dans l'environnement, puis
   reverrouille. Les autres profils qui ne l'utilisent pas ajoutent `--protect-keychain agent-vault`
   pour que leur agent ne puisse pas non plus le lire.
3. L'utilisateur déplace dans le coffre les secrets sensibles qu'il veut protéger (le skill ne
   copie rien depuis le trousseau de connexion).

Pour le détail des variables et des pièges de la sandbox, lire `references/profile-reference.md`.

## Utiliser un profil (rappel)

| But | Commande |
|---|---|
| Démarrer / reprendre | `agent-rc <p>` |
| Voir la session | `tmux attach -t <SESSION_NAME>` ; détacher : `Ctrl+B` puis `D` |
| Arrêter | `tmux kill-session -t <SESSION_NAME>` |
| État TokenEconomizer | `agent-rc <p> status` · `microskills` · `toolprune` |
| Régler les micro-skills d'un dépôt existant | dans le dépôt : `te config set microskills=on\|envfacts\|off` (effet au prochain hook) |
| Voir l'écran de la session sans s'y attacher (60 lignes, ou N en 3e argument) | `agent-rc <p> logs [N]` |
| Refus Seatbelt de la session + statistiques (journal `~/.local/state/agent-rc/<p>/blocks.jsonl`) | `agent-rc <p> blocks [durée] [--all] [--total]` (statistiques de la fenêtre ; `--total` : tout le journal) |
| Un outil a échoué : sandbox ou Claude Code ? | `agent-rc <p> why "<message d'erreur>"` (verdict SEATBELT / CLAUDE / INDETERMINE) |
| Mettre à jour le catalogue d'outils | `agent-rc <p> refresh-catalog` |
| Réafficher les outils masqués | `agent-rc <p> restore` |
| Démarrer sans hooks | `agent-rc <p> bypass` (`TE_DISABLE=1`) |

Les actions `status`…`restore` s'exécutent dans `PROJECT_DIR` sans entrer dans tmux. Si la
session existe déjà, `start` ne relance rien (verrou `.jsonl`) et affiche les commandes utiles.

## Limites à annoncer honnêtement

- La sandbox ne restreint que les **écritures** (hors `PROJECT_DIR`, `~/.claude`, `~/.claude.json` et ses
  fichiers frères `.claude.json.lock` / `.claude.json.tmp.*`, `~/Library/Caches/claude-cli-nodejs`,
  `~/.tokeneconomizer`, `~/.cargo`, `~/.rustup`, `/tmp`, `/private/tmp`, `/private/var/folders`).
  Les **lectures** restent libres : `~/.ssh` ou le trousseau de connexion sont lisibles par l'agent.
  Ce n'est pas une protection contre l'exfiltration. Seuls les trousseaux dédiés déclarés
  (`AGENT_KEYCHAIN`, `PROTECTED_KEYCHAINS`) sont refusés en lecture et en écriture.
  `/login` doit écrire dans le trousseau de connexion (via `security`, qui hérite de la sandbox) :
  sans `EXTRA_WRITE_PATHS="$HOME/Library/Keychains"` dans le profil, il échoue avec « Couldn't save
  your login ». À n'ajouter que pour un profil qui en a besoin.
- Coffre dédié : le mot de passe est demandé à chaque démarrage. Le coffre est déverrouillé
  quelques secondes pour tout le compte macOS (d'autres sessions non protégées pourraient le lire
  dans cette fenêtre), puis reverrouillé, avec un verrouillage automatique de secours après 5 min.
  Un agent dont la politique n'inclut pas le coffre (profil ancien, ou lancé sans `agent-rc`) peut
  le lire s'il connaît son chemin et qu'il est déverrouillé.
- Par défaut, les chemins d'écriture autorisés sont ceux d'un projet Rust. Un projet Node, Python
  (uv), Go, kubectl/helm/aws, etc. échouera sur ses caches (`~/.npm`, `~/.cache/uv`, `~/go`,
  `~/.kube/cache`…). Les étendre se fait par profil : `--write-path` à la création, ou la variable
  `EXTRA_WRITE_PATHS="/chemin1:/chemin2"` (absolus, séparés par `:`) dans le `.env`. Chaque chemin
  ajouté élargit ce que l'agent peut modifier : ne jamais ajouter `$HOME`, et éviter `~/.ssh`,
  `~/.gnupg`, `~/Library/Keychains` ou `~/.aws` en entier (le générateur avertit). Un changement
  de profil ne s'applique qu'au prochain démarrage de la session.
- Diagnostic des blocages : au démarrage, `agent-rc` enregistre les chemins de la politique dans
  `~/.local/state/agent-rc/<profil>/policy.paths` (lignes `home|allow|protect <chemin>`) et ajoute à l'agent (`--append-system-prompt`,
  désactivable avec `DIAG_HINT=0`) la consigne de lancer `agent-rc <profil> why "<erreur>"` quand un
  outil échoue, et de prévenir l'utilisateur si le verdict est SEATBELT. Le verdict combine : la
  politique enregistrée (chemin d'une erreur « Operation not permitted » hors des zones
  inscriptibles ⇒ SEATBELT, preuve fiable), le journal noyau (`log show`, lacunaire : doublons
  fusionnés, certains refus absents, et l'attribution à la session par arbre de processus est
  impossible depuis la sandbox où `ps` est bloqué) et des signatures d'erreurs Claude Code
  (`InputValidationError`, permissions, hooks…). « Permission denied » (EACCES) vient des droits
  Unix, pas de Seatbelt. Dans le dossier d'état, seul le journal `blocks.jsonl` est inscriptible
  par l'agent (la politique et la consigne ne le sont pas) : il est indicatif, pas une preuve d'audit.
- Reprise automatique : `agent-rc` répond à la question « Resume / Start a new conversation »
  (conversation ancienne ou volumineuse) en envoyant Entrée via `tmux send-keys` dès que le texte
  `Resuming it will use` apparaît (40 s max). Elle dépend de ce libellé : après une mise à jour de
  Claude Code, la question peut réapparaître sans erreur. Reprendre une grosse conversation coûte
  du quota. `AUTO_RESUME=0` dans le profil la désactive.
- `sandbox-exec` est déprécié par Apple mais fonctionnel.
- Le profil est sourcé deux fois (script, puis shell tmux) : un accès Keychain peut demander
  une autorisation deux fois la première fois.
