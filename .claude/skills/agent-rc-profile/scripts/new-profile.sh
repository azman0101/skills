#!/usr/bin/env bash
# Génère un profil agent-rc : ~/.config/agent-profiles/<nom>.env
# Compatible bash 3.2 (macOS). Aucun secret n'est lu ni écrit : seule la
# commande `security find-generic-password` est insérée dans le profil.
set -euo pipefail

PROFILES_DIR="${AGENT_PROFILES_DIR:-$HOME/.config/agent-profiles}"

usage() {
  cat >&2 <<'EOF'
Usage: new-profile.sh <nom> --project-dir DIR [options]

  --project-dir DIR     Dépôt de travail de l'agent (obligatoire, doit exister)
  --session NAME        Nom de session tmux        (défaut: claude-rc-<nom>)
  --rc-name NAME        Nom Remote Control         (défaut: <machine>-<nom>)
  --agent-cmd CMD       Binaire de l'agent         (défaut: claude)
  --resume UUID         Épingle une conversation à reprendre
  --resume-latest       Épingle la conversation la plus récente du projet
  --secret VAR=SERVICE[:COMPTE]
                        Variable alimentée depuis le Keychain (répétable).
                        COMPTE par défaut: $USER
  --microskills MODE    Micro-skills TokenEconomizer pour ce dépôt : envfacts (défaut,
                        apprend sans appel de modèle), on (ajoute un modèle toutes les 3 sessions,
                        coût imputé à la session), off, skip (ne rien changer).
                        Désactivés par défaut dans TokenEconomizer ; réglage hors du .env.
  --write-path PATH     Chemin supplémentaire en écriture dans la sandbox (répétable), ex: les
                        caches d'un outil (~/.kube/cache). Absolu ou ~/..., sans : ' " \
  --vault NOM|CHEMIN    Lit les --secret dans un trousseau dédié (voir vault.sh) au lieu du
                        trousseau de connexion. NOM sans '/' => ~/Library/Keychains/NOM.keychain-db.
                        Déverrouillé à la demande par agent-rc, reverrouillé après lecture, et
                        illisible pour l'agent (refus Seatbelt sur le fichier).
  --protect-keychain NOM|CHEMIN
                        Interdit aussi à l'agent la lecture de ce trousseau (répétable), ex: un
                        coffre de secrets que ce profil n'utilise pas.
  --otlp URL            Active la télémétrie OTLP vers URL (collecteur fourni par vous)
  --log-prompts         Avec --otlp : journalise aussi le texte des prompts
  --force               Écrase un profil existant
  --dry-run             Affiche le profil sur stdout sans rien écrire
EOF
  exit 2
}

die()  { echo "Erreur: $*" >&2; exit 1; }
warn() { echo "Attention: $*" >&2; }
sq()   { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }

[[ $# -ge 1 ]] || usage
NAME="$1"; shift
[[ "$NAME" =~ ^[a-z0-9][a-z0-9._-]*$ ]] || die "nom invalide '$NAME' (minuscules, chiffres, . _ -)"

PROJECT_DIR=""; SESSION=""; RC_NAME=""; AGENT_CMD="claude"; RESUME=""; RESUME_LATEST=0
OTLP=""; LOG_PROMPTS=0; FORCE=0; DRY=0; SECRETS=(); WRITE_PATHS=(); VAULT=""; PROTECT=(); MICROSKILLS="envfacts"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-dir)   PROJECT_DIR="${2:?}"; shift 2 ;;
    --session)       SESSION="${2:?}"; shift 2 ;;
    --rc-name)       RC_NAME="${2:?}"; shift 2 ;;
    --agent-cmd)     AGENT_CMD="${2:?}"; shift 2 ;;
    --resume)        RESUME="${2:?}"; shift 2 ;;
    --resume-latest) RESUME_LATEST=1; shift ;;
    --secret)        SECRETS+=("${2:?}"); shift 2 ;;
    --vault)         VAULT="${2:?}"; shift 2 ;;
    --protect-keychain) PROTECT+=("${2:?}"); shift 2 ;;
    --write-path)    WRITE_PATHS+=("${2:?}"); shift 2 ;;
    --microskills)   MICROSKILLS="${2:?}"; shift 2 ;;
    --otlp)          OTLP="${2:?}"; shift 2 ;;
    --log-prompts)   LOG_PROMPTS=1; shift ;;
    --force)         FORCE=1; shift ;;
    --dry-run)       DRY=1; shift ;;
    -h|--help)       usage ;;
    *) die "option inconnue: $1" ;;
  esac
done

case "$MICROSKILLS" in on|envfacts|off|skip) ;; *) die "--microskills: on|envfacts|off|skip" ;; esac
[[ -n "$PROJECT_DIR" ]] || die "--project-dir est obligatoire"
[[ -d "$PROJECT_DIR" ]] || die "dossier introuvable: $PROJECT_DIR"
# Seatbelt compare des chemins réels (ex: /tmp -> /private/tmp) : on résout les liens.
PROJECT_DIR="$(cd -P "$PROJECT_DIR" && pwd -P)"
# Le chemin est inséré dans une politique Seatbelt entre guillemets, elle-même
# dans une chaîne shell entre apostrophes : ces caractères la casseraient.
case "$PROJECT_DIR" in *\'*|*\"*|*\\*|*\$*|*\`*) die "le chemin contient un caractère interdit (' \" \\ \$ \`): $PROJECT_DIR" ;; esac
[[ "$PROJECT_DIR" == "$HOME" || "$PROJECT_DIR" == "/" ]] && die "PROJECT_DIR ne peut pas être \$HOME ou / (la sandbox n'aurait plus de sens)"

# Chemins d'écriture supplémentaires : EXTRA_WRITE_PATHS est une liste séparée par ':' lue par
# agent-rc, qui l'insère dans la politique Seatbelt (entre guillemets, dans une chaîne shell).
WRITE_RESOLVED=""
if (( ${#WRITE_PATHS[@]} )); then
  for p in "${WRITE_PATHS[@]}"; do
    case "$p" in "~") p="$HOME" ;; "~/"*) p="$HOME/${p#\~/}" ;; esac
    [[ "$p" == /* ]] || die "--write-path doit être un chemin absolu: $p"
    p="${p%/}"
    [[ -n "$p" ]] || die "--write-path ne peut pas être / (la sandbox n'aurait plus de sens)"
    # Seatbelt compare des chemins réels : on résout les liens quand le chemin (ou son parent) existe.
    if [[ -d "$p" ]]; then p="$(cd -P "$p" && pwd -P)"
    elif [[ -d "$(dirname "$p")" ]]; then d="$(cd -P "$(dirname "$p")" && pwd -P)"; p="${d%/}/$(basename "$p")"; fi
    case "$p" in *\'*|*\"*|*\\*|*:*|*$'\n'*) die "--write-path: caractère interdit (' \" \\ : saut de ligne): $p" ;; esac
    [[ -n "$p" && "$p" != "$HOME" && "$p" != "/" ]] || die "--write-path ne peut pas être \$HOME ou / (la sandbox n'aurait plus de sens)"
    case "$p" in
      "$HOME/.ssh"|"$HOME/.ssh/"*|"$HOME/.gnupg"|"$HOME/.gnupg/"*|"$HOME/Library/Keychains"|"$HOME/Library/Keychains/"*)
        warn "--write-path $p : l'agent pourra y modifier clés/identifiants (en lecture, il y accède déjà)" ;;
      "$HOME/.aws"|"$HOME/.aws/"*)
        warn "--write-path $p : zone d'identifiants AWS ; préférez les seuls sous-dossiers de cache nécessaires" ;;
    esac
    WRITE_RESOLVED="${WRITE_RESOLVED:+$WRITE_RESOLVED:}$p"
  done
fi

# Trousseaux dédiés : agent-rc interdit leur lecture à l'agent (règle Seatbelt sur le fichier).
# Le trousseau de connexion ne peut pas l'être : Claude Code y stocke ses propres identifiants.
resolve_kc() { bash "$(dirname "$0")/vault.sh" --vault "$1" path; }   # contrôles et résolution : vault.sh
VAULT_PATH=""; PROTECT_RESOLVED=""
[[ -z "$VAULT" ]] || VAULT_PATH="$(resolve_kc "$VAULT")"
if (( ${#PROTECT[@]} )); then
  for k in "${PROTECT[@]}"; do
    k="$(resolve_kc "$k")"
    [[ "$k" != "$VAULT_PATH" ]] && PROTECT_RESOLVED="${PROTECT_RESOLVED:+$PROTECT_RESOLVED:}$k"
  done
fi

SESSION="${SESSION:-claude-rc-$NAME}"
[[ "$SESSION" =~ ^[A-Za-z0-9_-]+$ ]] || die "nom de session tmux invalide '$SESSION' (évitez . et :)"
if [[ -z "$RC_NAME" ]]; then
  host="$(scutil --get ComputerName 2>/dev/null || hostname -s)"
  host="$(printf '%s' "$host" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g')"
  RC_NAME="$host-$NAME"
fi

if (( RESUME_LATEST )); then
  [[ -z "$RESUME" ]] || die "--resume et --resume-latest sont exclusifs"
  enc="$(printf '%s' "$PROJECT_DIR" | sed -E 's/[^A-Za-z0-9]/-/g')"
  latest="$(ls -t "$HOME/.claude/projects/$enc"/*.jsonl 2>/dev/null | head -1 || true)"
  if [[ -n "$latest" ]]; then RESUME="$(basename "$latest" .jsonl)"
  else warn "aucune conversation trouvée pour ce projet : le profil utilisera --continue"; fi
fi
if [[ -n "$RESUME" ]]; then
  [[ "$RESUME" =~ ^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$ ]] || die "UUID invalide: $RESUME"
fi

# Collisions avec les profils existants : deux profils sur la même session
# tmux ou le même dépôt se disputeraient le verrou .jsonl.
if [[ -d "$PROFILES_DIR" ]]; then
  for f in "$PROFILES_DIR"/*.env; do
    [[ -f "$f" && "$f" != "$PROFILES_DIR/$NAME.env" ]] || continue
    grep -qE "^SESSION_NAME=[\"']?$SESSION[\"']?\$" "$f" && warn "SESSION_NAME déjà utilisé par $(basename "$f")"
    grep -qE "^PROJECT_DIR=[\"']?$PROJECT_DIR[\"']?\$" "$f" && warn "PROJECT_DIR déjà utilisé par $(basename "$f")"
  done
fi

out=""
add() { out+="$1"$'\n'; }

add "# $PROFILES_DIR/$NAME.env  (généré par agent-rc-profile)"
add "PROJECT_DIR=$(sq "$PROJECT_DIR")"
add "SESSION_NAME=$(sq "$SESSION")"
add "RC_DISPLAY_NAME=$(sq "$RC_NAME")"
add "AGENT_CMD=$(sq "$AGENT_CMD")"
add ""
add "# UUID épinglé, ou vide pour --continue (dernière conversation du dossier)"
add "RESUME_UUID=$(sq "$RESUME")"
add ""
add "# TokenEconomizer (0 = actif, 1 = bypass)"
add 'export PATH="$HOME/.tokeneconomizer/bin:$PATH"'
add 'export TE_DISABLE="${TE_DISABLE:-0}"'

if [[ -n "$WRITE_RESOLVED" ]]; then
  add ""
  add "# Écritures supplémentaires autorisées dans la sandbox (chemins absolus séparés par :)"
  add "EXTRA_WRITE_PATHS=$(sq "$WRITE_RESOLVED")"
fi

if [[ -n "$VAULT_PATH" || -n "$PROTECT_RESOLVED" ]]; then
  add ""
  add "# Trousseaux dédiés : lecture interdite à l'agent par la sandbox (voir scripts/vault.sh)"
  [[ -z "$VAULT_PATH" ]] || add "AGENT_KEYCHAIN=$(sq "$VAULT_PATH")"
  [[ -z "$PROTECT_RESOLVED" ]] || add "PROTECTED_KEYCHAINS=$(sq "$PROTECT_RESOLVED")"
fi

if [[ -n "$OTLP" ]]; then
  add ""
  add "# Télémétrie OTLP"
  add "export CLAUDE_CODE_ENABLE_TELEMETRY=1"
  add "export OTEL_LOGS_EXPORTER=otlp"
  add "export OTEL_METRICS_EXPORTER=otlp"
  add "export OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf"
  add "export OTEL_EXPORTER_OTLP_ENDPOINT=$(sq "$OTLP")"
  (( LOG_PROMPTS )) && add "export OTEL_LOG_USER_PROMPTS=1"
fi

if (( ${#SECRETS[@]} )); then
  add ""
  add "# Secrets : lus dans le Keychain, jamais passés en argument de commande."
  add "# Affectation séparée de l'export : si l'entrée manque, set -e interrompt agent-rc"
  add "# au lieu de lancer l'agent avec une variable vide."
  add "# Ignorés quand agent-rc n'en a pas besoin (status, microskills…)."
  add 'if [[ -z "${AGENT_SKIP_SECRETS:-}" ]]; then'
  [[ -z "$VAULT_PATH" || -f "$VAULT_PATH" ]] || warn "coffre introuvable: $VAULT_PATH (créez-le avec scripts/vault.sh init)"
  kc_arg=""; [[ -z "$VAULT_PATH" ]] || kc_arg=' "$AGENT_KEYCHAIN"'
  for s in "${SECRETS[@]}"; do
    var="${s%%=*}"; rest="${s#*=}"
    [[ "$s" == *=* && -n "$rest" ]] || die "--secret attend VAR=SERVICE[:COMPTE], reçu '$s'"
    [[ "$var" =~ ^[A-Z_][A-Z0-9_]*$ ]] || die "nom de variable invalide: $var"
    service="${rest%%:*}"; account="$USER"; [[ "$rest" == *:* ]] && account="${rest#*:}"
    if [[ -z "$VAULT_PATH" || -f "$VAULT_PATH" ]] \
       && ! security find-generic-password -s "$service" -a "$account" ${VAULT_PATH:+"$VAULT_PATH"} >/dev/null 2>&1; then
      if [[ -n "$VAULT_PATH" ]]; then
        warn "entrée absente du coffre (service='$service', compte='$account'). Ajoutez-la avec :"
        warn "  vault.sh --vault '$VAULT' add '$service' '$account'   # saisie masquée"
      else
        warn "entrée Keychain introuvable (service='$service', compte='$account'). Créez-la avec :"
        warn "  security add-generic-password -s '$service' -a '$account' -w   # saisie masquée"
      fi
    fi
    add "  $var=\"\$(security find-generic-password -s $(sq "$service") -a $(sq "$account") -w$kc_arg)\""
    add "  export $var"
  done
  add "fi"
fi

if (( DRY )); then printf '%s' "$out"; exit 0; fi

mkdir -p "$PROFILES_DIR"
target="$PROFILES_DIR/$NAME.env"
[[ ! -e "$target" || $FORCE -eq 1 ]] || die "$target existe déjà (utilisez --force)"
umask 077
printf '%s' "$out" > "$target"
chmod 600 "$target"
if [[ "$MICROSKILLS" != "skip" ]]; then
  # `te` est installé par TokenEconomizer (pip --user) ; on complète le PATH sans le préempter.
  PATH="$PATH:$HOME/.tokeneconomizer/bin"
  for d in "$HOME"/Library/Python/*/bin; do [[ -d "$d" ]] && PATH="$PATH:$d"; done
  if command -v te >/dev/null 2>&1; then
    (cd "$PROJECT_DIR" && te config set "microskills=$MICROSKILLS" >/dev/null) \
      && echo "Micro-skills : $MICROSKILLS (dépôt $PROJECT_DIR)" \
      || warn "échec de 'te config set microskills=$MICROSKILLS'"
  else
    warn "'te' introuvable : micro-skills non configurés. Dans le dépôt : te config set microskills=$MICROSKILLS"
  fi
fi
echo "Profil créé : $target"
echo "  Lancer     : agent-rc $NAME"
echo "  Attacher   : tmux attach -t $SESSION"
