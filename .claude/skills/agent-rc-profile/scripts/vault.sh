#!/usr/bin/env bash
# Gère le trousseau dédié ("coffre") des secrets d'un profil agent-rc.
# Mots de passe et secrets sont lus sans écho et transmis à `security -i` par l'entrée standard :
# ils n'apparaissent dans les arguments d'aucun processus (visibles par `ps`).
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: vault.sh [--vault NOM|CHEMIN] <commande>

  init                      Crée le coffre (mot de passe demandé deux fois), verrouillage auto 5 min
  add SERVICE [COMPTE]      Ajoute ou met à jour un secret (valeur demandée sans écho). COMPTE: $USER
  unlock                    Déverrouille (mot de passe demandé)
  lock                      Verrouille
  status                    État du coffre
  path                      Affiche le chemin du fichier

NOM sans '/' => ~/Library/Keychains/NOM.keychain-db ; défaut: agent-vault.
Le coffre n'est PAS ajouté à la liste de recherche du trousseau : `security find-generic-password`
sans chemin explicite ne le voit pas.
EOF
  exit 2
}

die() { echo "Erreur: $*" >&2; exit 1; }

VAULT="agent-vault"
if [[ "${1:-}" == "--vault" ]]; then VAULT="${2:?}"; shift 2; fi
[[ $# -ge 1 ]] || usage
cmd="$1"; shift

# Résolution du trousseau, partagée avec new-profile.sh (`vault.sh --vault X path`).
case "$VAULT" in
  "~/"*) K="$HOME/${VAULT#\~/}" ;;
  */*)   K="$VAULT" ;;
  *)     K="$HOME/Library/Keychains/${VAULT%.keychain-db}.keychain-db" ;;
esac
[[ "$K" == /* ]] || die "chemin du coffre non absolu: $K"
case "$K" in *\'*|*\"*|*\\*|*:*|*$'\n'*) die "caractère interdit dans le chemin (' \" \\ : saut de ligne): $K" ;; esac
case "$(basename "$K")" in login.keychain*|metadata.keychain*|System.keychain*)
  die "trousseau '$K' géré par macOS : l'interdire casserait Claude Code" ;; esac
# Seatbelt compare des chemins réels : on résout les liens du dossier parent quand il existe.
if [[ -d "$(dirname "$K")" ]]; then d="$(cd -P "$(dirname "$K")" && pwd -P)"; K="${d%/}/$(basename "$K")"; fi

# Lecture sans écho ; le prompt n'apparaît que sur un terminal.
ask() { read -rsp "$1" REPLY || true; [[ ! -t 0 ]] || echo >&2; }

case "$cmd" in
  init)
    [[ ! -e "$K" ]] || die "$K existe déjà"
    mkdir -p "$(dirname "$K")"
    ask "Mot de passe du coffre : "; pw1="$REPLY"
    ask "Confirmation           : "; pw2="$REPLY"
    [[ -n "$pw1" && "$pw1" == "$pw2" ]] || die "mots de passe vides ou différents"
    printf 'create-keychain -p %q %q\n' "$pw1" "$K" | security -i >/dev/null
    unset pw1 pw2
    chmod 600 "$K"
    security set-keychain-settings -t 300 -l "$K"   # verrouillage auto après 5 min et à la mise en veille
    security lock-keychain "$K"
    echo "Coffre créé et verrouillé : $K"
    echo "Ajoutez un secret : vault.sh$([[ "$VAULT" == agent-vault ]] || echo " --vault $VAULT") add SERVICE [COMPTE]"
    ;;
  unlock) exec security unlock-keychain "$K" ;;
  lock)   security lock-keychain "$K" && echo "Coffre verrouillé." ;;
  add)
    service="${1:?SERVICE manquant}"; account="${2:-$USER}"
    [[ -f "$K" ]] || die "coffre introuvable: $K (vault.sh init)"
    trap 'security lock-keychain "$K" >/dev/null 2>&1 || true' EXIT   # toujours reverrouillé après un ajout
    if [[ -z "${VAULT_ASSUME_UNLOCKED:-}" ]]; then   # =1 : coffre déjà déverrouillé (usage scripté)
      echo "Déverrouillage du coffre…" >&2
      security unlock-keychain "$K"
    fi
    ask "Valeur du secret ($service / $account) : "; val="$REPLY"
    [[ -n "$val" ]] || die "valeur vide"
    printf 'add-generic-password -U -s %q -a %q -w %q %q\n' "$service" "$account" "$val" "$K" | security -i >/dev/null
    unset val
    security find-generic-password -s "$service" -a "$account" "$K" >/dev/null 2>&1 \
      && echo "Secret enregistré (service='$service', compte='$account')." \
      || die "échec de l'enregistrement"
    ;;
  status)
    [[ -f "$K" ]] || { echo "Coffre absent : $K (vault.sh init)"; exit 1; }
    echo "Fichier     : $K ($(ls -ld "$K" | cut -c1-10))"
    security list-keychains -d user | grep -qF "$K" \
      && echo "Recherche   : DANS la liste de recherche (l'agent le verrait par défaut)" \
      || echo "Recherche   : hors de la liste de recherche (attendu)"
    if info="$(security show-keychain-info "$K" 2>&1)"; then echo "Réglages    : ${info#*Keychain }"
    else echo "Réglages    : illisibles (coffre verrouillé : normal)"; fi
    ;;
  path) echo "$K" ;;
  *) usage ;;
esac
