# TODO — agent-rc-profile

Idées retenues lors de la relecture `/simplify` mais **non implémentées**, un défaut observé en usage
réel, et la conception (sans réalisation) d'un mode d'apprentissage.

## 1. À corriger

- [x] **Fichiers de verrou de `~/.claude.json` refusés** — corrigé. La politique autorise maintenant
  `~/.claude.json` et ses fichiers frères par une règle `regex` (`^<HOME>/\.claude\.json(\..*)?$`, chemin
  échappé), ainsi que `~/Library/Caches/claude-cli-nodejs` (journaux MCP). `policy.paths` porte une ligne
  `allowprefix` correspondante. Vérifié : `.claude.json`, `.lock` et `.tmp.*` passent ; `.claude.jsonX`,
  `.claude.json2` et les autres fichiers restent refusés. À confirmer en conditions réelles :
  `agent-rc <profil> blocks 15m` ne doit plus montrer de refus sur ces chemins après un redémarrage.

## 2. Issues du `/simplify`, non appliquées

| Idée | Intérêt | Réserve |
|---|---|---|
| Sortir le Python dans `scripts/agent-rc-diag.py`, installé à côté d'`agent-rc` | Testable, lintable, plus de contraintes de quoting heredoc | Change la commande d'installation (aujourd'hui un seul fichier copié) |
| `sandbox-exec -f "$STATE_DIR/policy.sb"` au lieu de `-p '…'` | Une seule source de vérité ; supprime la contrainte « pas de `'` dans les chemins » | Le fichier doit rester non inscriptible par l'agent (c'est le cas : seul `blocks.jsonl` l'est) |
| Échapper `\` et `"` (`sbpl_str()`) au lieu de refuser ces caractères | Moins de cas refusés, une seule règle partagée par `agent-rc`, `new-profile.sh`, `vault.sh` | Changement de comportement |
| Marquer les règles `(with message "agent-rc:<profil>")` et filtrer `log show` dessus | Attribution exacte des refus, y compris pour les processus déjà terminés | Non vérifié : un essai n'a pas fait apparaître le message dans le journal noyau |
| Hook `PostToolUseFailure` injecté via `--settings` | Classement automatique des échecs, sans dépendre du texte collé par l'agent ; la consigne et la plupart des signatures d'erreurs disparaissent | Vérifier les événements de hook de la version de Claude Code installée |
| `sandbox_check()` (libsystem_sandbox) pour interroger le noyau | Remplace `policy_block`, qui approxime l'évaluation des règles | API non documentée, à appeler depuis le PID de l'agent |
| Rotation du journal `blocks.jsonl` (N dernières entrées ou 30 jours) | Il grossit sans limite et est relu en entier | Négligeable à ce volume |
| Option `--agent-cmd` de `new-profile.sh` qui écrit `DIAG_HINT` ou `AGENT_ARGS` dans le `.env` | Évite de deviner via le premier mot d'`AGENT_CMD` (cas d'un script enveloppe) | — |
| Surveillance continue côté hôte (collecte `log stream` pendant la session) | Le journal noyau est lacunaire et ne se relit pas depuis la sandbox ; sert aussi à la section 3 | Un processus de plus à gérer (tmux, launchd) |
| Supprimer `VAULT_ASSUME_UNLOCKED` de `vault.sh` | Variable inutilisée dans le dépôt | Peut servir à un usage scripté : à trancher |
| Une seule description du coffre dans la doc | Le texte figure dans `README.md`, `SKILL.md` et `profile-reference.md` | Garder la version complète dans `profile-reference.md` et y renvoyer |

## 3. Mode d'apprentissage (conception, non implémenté)

**But.** Partir des blocages récurrents pour proposer à l'utilisateur des chemins à autoriser
(`EXTRA_WRITE_PATHS`), au lieu de les découvrir un par un. La décision reste humaine.

### Interface proposée

```sh
agent-rc <profil> learn [durée]           # rapport seul, lecture (défaut 7d)
agent-rc <profil> learn --apply           # applique après confirmation interactive, avec sauvegarde
agent-rc <profil> learn --reject <chemin> # ne plus proposer ce chemin
```

`blocks` terminerait par « `agent-rc <profil> learn` pour des suggestions » quand des refus se répètent.

### Données et confiance

- **Source de référence : le journal noyau, collecté côté hôte.** Le fichier `blocks.jsonl` est inscriptible
  par l'agent : un agent compromis ou mal guidé pourrait y forger des refus pour amener l'utilisateur à
  ouvrir un chemin sensible. Les entrées `toolfail` viennent de l'agent : poids faible, jamais seules.
- Ne compter que les refus **attribués** à la session (arbre de processus) et les écritures
  (`file-write-*`) ; les lectures ne sont refusées que sur les trousseaux protégés, volontairement.
- La collecte continue (section 2) rend les comptes fiables ; sans elle, ils sont des minorants.

### Du refus à la suggestion

1. **Normaliser** : `.tmp.<pid>.<hex>` → `.tmp.*`, UUID, horodatages et nombres → jokers.
2. **Regrouper** par (opération, chemin normalisé), puis remonter au plus petit dossier commun quand
   au moins *k* frères distincts sont refusés (fichier seul sinon).
3. **Seuils** : au moins *N* occurrences, sur au moins *M* sessions ou jours distincts, pour éviter
   qu'un incident isolé devienne une règle.
4. **Catalogue de préréglages** : un préfixe connu devient un nom d'écosystème, avec les chemins déjà
   utilisés dans ce dépôt (`~/.cargo`, `~/.npm`, `~/.cache/uv`, `~/go`, `~/Library/Caches/go-build`,
   `~/.kube/cache`, caches `helm` et `aws`). Exemple : « 40 refus dans le cache go-build → préréglage go ».
5. **Défauts internes à Claude Code** (`~/.claude.json.*`, caches `claude-cli-nodejs`) : proposer de les
   intégrer à la politique par défaut du skill, pas dans chaque profil.

### Garde-fous

- Jamais de suggestion pour `$HOME`, `/`, `~/.ssh`, `~/.gnupg`, `~/Library/Keychains` entier, ni les
  zones d'identifiants AWS hors sous-dossiers de cache : mêmes règles et mêmes avertissements que
  `new-profile.sh`. Ces chemins peuvent apparaître en information, jamais en proposition applicable.
- Chaque suggestion porte un **niveau de risque** (cache jetable / données du projet / identifiants),
  les événements qui la motivent (3 exemples) et la ligne exacte à ajouter.
- `--apply` : affiche le diff du `.env`, demande confirmation, sauvegarde l'ancien fichier hors du
  dossier des profils (un `*.bak` à cet endroit serait listé comme profil), puis rappelle de redémarrer
  la session. L'agent ne peut jamais déclencher `learn --apply`.
- Les rejets sont mémorisés dans `learn.json` (dossier d'état, non inscriptible par l'agent).

### Phasage

1. Rapport seul (`learn`), à partir de la collecte actuelle. Valide les seuils sur des données réelles.
2. Catalogue de préréglages et regroupement par dossier.
3. `--apply` avec diff, confirmation, sauvegarde et mémoire des rejets.
4. Collecte continue côté hôte, puis recoupement multi-profils (même chemin refusé dans plusieurs
   profils → candidat au défaut du skill).

### Questions ouvertes

- Rétention du journal noyau : combien de jours de refus `log show` restitue-t-il réellement ?
- Valeurs de *N*, *M* et *k* : à calibrer sur les profils `ksm-migrator` et `frigate-labeler`.
- Faut-il distinguer « autoriser l'écriture » de « laisser échouer, l'outil a un repli » ? Les refus de
  `~/.claude.json.lock` seraient peut-être à ignorer si Claude Code s'en accommode.
