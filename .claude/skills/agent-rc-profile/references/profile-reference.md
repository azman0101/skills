# Référence du fichier profil

Fichier : `~/.config/agent-profiles/<nom>.env`, sourcé par `agent-rc` (zsh, `set -euo pipefail`)
puis une seconde fois dans le shell tmux.

## Variables lues par agent-rc

| Variable | Rôle | Obligatoire |
|---|---|---|
| `PROJECT_DIR` | Répertoire de travail ET seul dossier utilisateur écrivable dans la sandbox. Chemin réel (sans lien symbolique) | oui |
| `SESSION_NAME` | Nom de la session tmux, sert aussi de garde d'idempotence | oui |
| `RC_DISPLAY_NAME` | Nom affiché par `--remote-control` | oui |
| `AGENT_CMD` | Binaire lancé (défaut `claude`) | non |
| `RESUME_UUID` | Si renseigné : `--resume UUID` ; vide : `--continue` | non |
| `EXTRA_WRITE_PATHS` | Chemins absolus supplémentaires en écriture dans la sandbox, séparés par `:` (sans `'` `"` `\`). Absent ou vide : politique par défaut inchangée | non |
| `AUTO_RESUME` | `1` (défaut) : valide automatiquement la question de reprise ; `0` : la laisse à l'utilisateur | non |
| `TE_DISABLE` | `0` TokenEconomizer actif, `1` bypass (posé par l'action `bypass`) | non |

Tout `export` du profil (OTEL_*, clés, etc.) est hérité par l'agent.

## Télémétrie OTLP (optionnelle)

`CLAUDE_CODE_ENABLE_TELEMETRY=1`, `OTEL_LOGS_EXPORTER=otlp`, `OTEL_METRICS_EXPORTER=otlp`,
`OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf`, `OTEL_EXPORTER_OTLP_ENDPOINT=<url>`.
`OTEL_LOG_USER_PROMPTS=1` envoie le **texte des prompts** au collecteur : à n'activer que pour un
collecteur de confiance, et le dire à l'utilisateur.

## Micro-skills TokenEconomizer

Désactivés par défaut dans TokenEconomizer. Le réglage est **par dépôt** et vit dans
`~/.tokeneconomizer/repos/<dépôt>/config.json`, pas dans le profil. Le générateur lance
`te config set microskills=<mode>` dans `PROJECT_DIR`.

| Mode | Effet |
|---|---|
| `envfacts` (défaut du générateur) | faits appris des sessions terminées, sans appel de modèle |
| `on` (= `envfacts+distiller`) | idem, plus propositions d'un modèle toutes les 3 sessions. **Coût : chaque proposition est un appel de modèle imputé à la session**, donc du quota consommé en plus |
| `off` | désactivé |

Vérifier : `te config show` dans le dépôt. Afficher les faits : `agent-rc <profil> microskills`.

## Secrets

Forme à utiliser :

```zsh
MA_CLE="$(security find-generic-password -s 'service' -a 'compte' -w)"
export MA_CLE
```

Ne pas écrire `export MA_CLE="$(...)"` : `export` masque le code de retour de la substitution,
donc une entrée absente donnerait une variable vide sans erreur, et l'agent démarrerait sans la clé.
La valeur reste dans l'environnement du processus, pas dans la ligne de commande (`ps aux`).
Elle est en revanche visible de l'agent lui-même (`env`), ce qui est voulu.

## Pièges de construction

- **Quotes dans `PROJECT_DIR`** : le chemin est inséré dans une politique Seatbelt entre `"` puis
  dans une chaîne shell entre `'`. Les caractères `' " \ $ \`` y sont interdits (le générateur refuse).
- **Liens symboliques** : Seatbelt compare des chemins réels. `/tmp` est `/private/tmp`; un dépôt
  atteint via un lien serait en écriture refusée. Le générateur applique `cd -P`.
- **`SESSION_NAME`** : éviter `.` et `:` (séparateurs tmux). Deux profils sur le même dépôt ou la même
  session se disputent le verrou `.jsonl` : un seul profil par dépôt.
- **Reprise** : les conversations sont dans `~/.claude/projects/<chemin-aplati>/<uuid>.jsonl`, où
  le chemin du dépôt est aplati en remplaçant tout caractère non alphanumérique par `-`.
  `--resume-latest` prend le fichier le plus récent.
- **Permissions** : le profil peut contenir des commandes d'accès aux secrets, `chmod 600`.

## Dépannage

| Symptôme | Cause probable |
|---|---|
| `Profile not found` | mauvais nom, ou fichier hors de `~/.config/agent-profiles/` |
| `Session ... already running` | normal : `tmux attach -t <SESSION_NAME>` |
| `EXTRA_WRITE_PATHS: chemin refusé` au lancement | chemin relatif, ou contenant `'` `"` `\` ; corriger le profil |
| L'agent démarre puis `Operation not permitted` à l'écriture | chemin hors liste d'écriture de la sandbox (cache npm/uv/go…) : l'ajouter dans `EXTRA_WRITE_PATHS` (`--write-path`) et redémarrer la session |
| Code 44 / `could not be found in the keychain` au lancement | entrée Keychain absente (service/compte) |
| `te: command not found` | TokenEconomizer non installé; voir `~/.local/share/claude-plugins/TokenEconomizer` |
| La question « Resume / Start a new conversation » reste affichée | libellé changé dans une nouvelle version de Claude Code (adapter le `grep` de `agent-rc`), ou `AUTO_RESUME=0` |
| L'agent s'arrête mais la session tmux reste | normal : `exec zsh` garde un shell ouvert; `tmux attach` pour lire l'erreur |
