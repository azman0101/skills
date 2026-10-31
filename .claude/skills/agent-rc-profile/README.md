# agent-rc-profile

Skill [Claude Code](https://claude.com/claude-code) pour créer et utiliser des profils `agent-rc` :
un agent Claude Code lancé en arrière-plan dans une session **tmux**, avec Remote Control,
`caffeinate`, une sandbox macOS (`sandbox-exec`) et, en option, TokenEconomizer.

Un profil = un dépôt = une session tmux. Le skill génère le fichier
`~/.config/agent-profiles/<nom>.env` et rappelle les commandes d'usage.

## Prérequis

- macOS (Keychain et `sandbox-exec`), zsh, `tmux`, Claude Code.
- Le lanceur **`agent-rc`**, fourni dans `scripts/agent-rc`. Il source
  `~/.config/agent-profiles/<profil>.env`, lit `PROJECT_DIR`, `SESSION_NAME`, `RC_DISPLAY_NAME`,
  `AGENT_CMD`, `RESUME_UUID`, et démarre `tmux new -d` avec `caffeinate -is sandbox-exec …`.

## Installation

```bash
git clone git@github.com:azman0101/skills.git && cd skills
ln -s "$PWD/.claude/skills/agent-rc-profile" ~/.claude/skills/agent-rc-profile
mkdir -p ~/.local/bin && install -m 755 .claude/skills/agent-rc-profile/scripts/agent-rc ~/.local/bin/agent-rc
```

Vérifiez que `~/.local/bin` est dans votre `PATH`. `agent-rc` n'a pas de profil par défaut :
`agent-rc <profil> [start|status|logs|blocks|why|microskills|toolprune|refresh-catalog|restore|bypass]`.

Rechargez les skills (`/reload-skills`) ou relancez Claude Code.

## Utilisation

Dans Claude Code : `/agent-rc-profile`, ou demandez « crée un profil agent-rc pour ce dépôt ».
Le générateur peut aussi s'utiliser seul :

```bash
bash scripts/new-profile.sh mon-projet --project-dir ~/code/mon-projet \
  --secret API_KEY=mon-service --resume-latest --dry-run
```

Options : `--session`, `--rc-name`, `--agent-cmd`, `--vault NOM`, `--protect-keychain NOM` (trousseau dédié, voir plus bas), `--write-path CHEMIN` (répétable : dossiers supplémentaires en écriture dans la sandbox, par exemple
les caches d'un outil), `--microskills envfacts|on|off|skip` (défaut `envfacts` :
active les micro-skills TokenEconomizer du dépôt, désactivés par défaut chez eux, sans appel de
modèle ; `on` ajoute un modèle toutes les 3 sessions, au coût de la session),
`--resume UUID | --resume-latest`,
`--secret VAR=SERVICE[:COMPTE]` (répétable), `--otlp URL [--log-prompts]`, `--force`, `--dry-run`.
Sans `--dry-run`, le profil est écrit en `chmod 600` ; un profil existant n'est jamais écrasé sans
`--force`. `AGENT_PROFILES_DIR` change le dossier de destination.

## Sécurité

- Les secrets sont lus dans le Keychain au lancement. Le skill ne les lit, ne les demande et ne
  les écrit jamais.
- La sandbox ne restreint que les **écritures** ; les lectures restent libres. Ce n'est pas une
  protection contre l'exfiltration. Exception : les trousseaux dédiés déclarés dans un profil.
- **Coffre dédié.** Le Keychain ne se filtre pas par nom de secret, mais `sandbox-exec` peut interdire
  la lecture du *fichier* d'un trousseau précis, ce qui bloque `security` même déverrouillé.
  `scripts/vault.sh init|add|unlock|lock|status` gère un trousseau séparé ; `--vault` y lit les
  secrets d'un profil (mot de passe demandé à chaque démarrage, reverrouillage après lecture),
  `--protect-keychain` le cache aux autres profils. Le trousseau de connexion ne peut pas être
  protégé ainsi : Claude Code y stocke ses identifiants.
- La télémétrie OTLP est désactivée par défaut. `--log-prompts` envoie le texte des prompts à votre
  collecteur : à n'utiliser qu'avec un collecteur de confiance.
- `sandbox-exec` est déprécié par Apple mais fonctionnel.

## Contenu

| Fichier | Rôle |
|---|---|
| `SKILL.md` | Instructions du skill |
| `scripts/new-profile.sh` | Générateur de profils |
| `scripts/vault.sh` | Trousseau dédié (coffre) pour les secrets |
| `scripts/agent-rc` | Lanceur (tmux, sandbox, reprise automatique) |
| `references/profile-reference.md` | Variables, pièges, dépannage |

## Licence

[0BSD](LICENSE) : utilisation, copie, modification et redistribution libres, sans obligation de
conserver la mention de copyright.
