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
   - **secrets** : noms de variables et entrées Keychain (jamais les valeurs) ;
   - **télémétrie OTLP** : optionnelle, désactivée par défaut. N'en proposer aucun endpoint :
     l'utilisateur fournit le sien s'il a un collecteur (et dit si les prompts sont journalisés) ;
   - **micro-skills TokenEconomizer** : désactivés par défaut dans TokenEconomizer, ce skill les
     active en `envfacts` (apprentissage sans appel de modèle). Le mode `on` ajoute un modèle qui
     propose des faits toutes les 3 sessions, **coût imputé à la session** : ne le choisir que si
     l'utilisateur le demande, en le lui signalant ;
   - **reprise** : conversation précise (UUID), la plus récente, ou `--continue` par défaut.
3. Générer avec le script (toujours `--dry-run` d'abord si l'utilisateur hésite) :

```bash
bash <skill>/scripts/new-profile.sh <nom> --project-dir <dépôt> \
  [--secret VAR=SERVICE[:COMPTE]]... [--otlp URL [--log-prompts]] \
  [--microskills envfacts|on|off|skip] [--resume UUID | --resume-latest] [--session N] [--rc-name N] [--agent-cmd C] [--force]
```

   Il valide les entrées, résout les liens symboliques du dépôt, signale les collisions de
   session/dépôt avec d'autres profils, vérifie la présence des entrées Keychain sans lire leur
   valeur, et écrit le fichier en `chmod 600`. Il n'écrase rien sans `--force`. Il exécute aussi
   `te config set microskills=<mode>` dans le dépôt (réglage stocké dans `~/.tokeneconomizer`, pas
   dans le `.env`, par dépôt) ; sans `te` installé, il affiche la commande à lancer.
4. Si une entrée Keychain manque, **ne pas** demander le secret dans le chat. Donner la commande
   `security add-generic-password -s SERVICE -a COMPTE -w` à lancer par l'utilisateur (saisie masquée).
5. Lancer `agent-rc <nom>`, puis confirmer avec `tmux has-session -t <session>`.

Pour le détail des variables et des pièges de la sandbox, lire `references/profile-reference.md`.

## Utiliser un profil (rappel)

| But | Commande |
|---|---|
| Démarrer / reprendre | `agent-rc <p>` |
| Voir la session | `tmux attach -t <SESSION_NAME>` ; détacher : `Ctrl+B` puis `D` |
| Arrêter | `tmux kill-session -t <SESSION_NAME>` |
| État TokenEconomizer | `agent-rc <p> status` · `microskills` · `toolprune` |
| Régler les micro-skills d'un dépôt existant | dans le dépôt : `te config set microskills=on\|envfacts\|off` (effet au prochain hook) |
| Mettre à jour le catalogue d'outils | `agent-rc <p> refresh-catalog` |
| Réafficher les outils masqués | `agent-rc <p> restore` |
| Démarrer sans hooks | `agent-rc <p> bypass` (`TE_DISABLE=1`) |

Les actions `status`…`restore` s'exécutent dans `PROJECT_DIR` sans entrer dans tmux. Si la
session existe déjà, `start` ne relance rien (verrou `.jsonl`) et affiche les commandes utiles.

## Limites à annoncer honnêtement

- La sandbox ne restreint que les **écritures** (hors `PROJECT_DIR`, `~/.claude`, `~/.claude.json`,
  `~/.tokeneconomizer`, `~/.cargo`, `~/.rustup`, `/tmp`, `/private/tmp`, `/private/var/folders`).
  Les **lectures** restent libres : `~/.ssh` ou le trousseau sont lisibles par l'agent. Ce n'est
  pas une protection contre l'exfiltration.
- Les chemins d'écriture autorisés sont codés en dur dans `agent-rc`, pensés pour Rust. Un projet
  Node, Python (uv), Go, etc. échouera sur ses caches (`~/.npm`, `~/.cache/uv`, `~/go`…). Il n'y a
  pas de variable de profil pour les étendre : l'ajouter demande de modifier le script `agent-rc`
  (par ex. une variable `EXTRA_WRITE_PATHS`). Proposer ce changement, ne pas l'appliquer sans accord.
- Reprise automatique : `agent-rc` répond à la question « Resume / Start a new conversation »
  (conversation ancienne ou volumineuse) en envoyant Entrée via `tmux send-keys` dès que le texte
  `Resuming it will use` apparaît (40 s max). Elle dépend de ce libellé : après une mise à jour de
  Claude Code, la question peut réapparaître sans erreur. Reprendre une grosse conversation coûte
  du quota. `AUTO_RESUME=0` dans le profil la désactive.
- `sandbox-exec` est déprécié par Apple mais fonctionnel.
- Le profil est sourcé deux fois (script, puis shell tmux) : un accès Keychain peut demander
  une autorisation deux fois la première fois.
