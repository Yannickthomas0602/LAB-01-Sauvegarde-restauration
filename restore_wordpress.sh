#!/usr/bin/env bash
set -Eeuo pipefail

# ==============================
# CONFIGURATION
# ==============================

WEB_DIR="/var/www/html"

SSH_USER="yannick"
SSH_HOST="192.168.137.61"
SSH_PORT="2224"
REMOTE_DIR="/home/yannick/backups/wordpress"

SSH_KEY="/root/.ssh/wordpress_backup"

SSH_OPTS=(-p "$SSH_PORT" -i "$SSH_KEY" -o BatchMode=yes)
REMOTE="${SSH_USER}@${SSH_HOST}"

TMP_DIR=$(mktemp -d)
MAINTENANCE="$WEB_DIR/.maintenance"

cleanup() {
    rm -rf "$TMP_DIR"
    rm -f "$MAINTENANCE"
}
trap cleanup EXIT

# ==============================
# VERIFICATIONS
# ==============================

if [[ $EUID -ne 0 ]]; then
    echo "ERREUR : lancer ce script avec sudo ou en root."
    exit 1
fi

for CMD in ssh scp tar rsync; do
    command -v "$CMD" >/dev/null || {
        echo "ERREUR : commande manquante : $CMD"
        exit 1
    }
done

if [[ ! -d "$WEB_DIR" ]]; then
    echo "Répertoire WordPress introuvable : $WEB_DIR"
    exit 1
fi

echo "=================================="
echo " RESTAURATION WORDPRESS"
echo "=================================="

# ==============================
# LISTE DES ARCHIVES
# ==============================

echo "Recherche des sauvegardes distantes..."

LIST=$(ssh "${SSH_OPTS[@]}" "$REMOTE" \
    "find '$REMOTE_DIR' -maxdepth 1 -type f -name 'wordpress_*.tar.gz' -printf '%f\n' | sort -r")

if [[ -z "$LIST" ]]; then
    echo "Aucune archive disponible."
    exit 1
fi

mapfile -t ARCHIVES <<< "$LIST"

echo
echo "Archives disponibles :"
echo

select ARCHIVE in "${ARCHIVES[@]}"; do
    if [[ -n "${ARCHIVE:-}" ]]; then
        break
    fi
    echo "Sélection invalide."
done

echo
echo "Archive sélectionnée : $ARCHIVE"

# ==============================
# CONFIRMATION
# ==============================

echo
echo "ATTENTION : le contenu actuel de $WEB_DIR"
echo "sera remplacé par celui de l'archive."

read -r -p "Confirmer la restauration ? (oui/non) : " CONFIRM

if [[ "$CONFIRM" != "oui" ]]; then
    echo "Restauration annulée."
    exit 0
fi

# ==============================
# TELECHARGEMENT
# ==============================

echo
echo "[1/5] Téléchargement..."

scp -P "$SSH_PORT" -i "$SSH_KEY" \
    -o BatchMode=yes \
    "${REMOTE}:${REMOTE_DIR}/${ARCHIVE}" \
    "$TMP_DIR/$ARCHIVE"

# ==============================
# VERIFICATION ARCHIVE
# ==============================

echo "[2/5] Vérification de l'archive..."

tar -tzf "$TMP_DIR/$ARCHIVE" >/dev/null

# Protection contre les chemins dangereux
if ! tar -tzf "$TMP_DIR/$ARCHIVE" | awk '
{
    path = $0
    if (path ~ /^\//) exit 1
    sub(/^(\.\/)+/, "", path)
    n = split(path, parts, "/")
    for (i = 1; i <= n; i++) {
        if (parts[i] == "..") exit 1
    }
}
'; then
    echo "ERREUR : chemins dangereux détectés dans l'archive."
    exit 1
fi

# ==============================
# EXTRACTION TEMPORAIRE
# ==============================

echo "[3/5] Extraction temporaire..."

mkdir "$TMP_DIR/extracted"

tar --no-same-owner -xzpf "$TMP_DIR/$ARCHIVE" \
    -C "$TMP_DIR/extracted"

# ==============================
# SAUVEGARDE DE SECURITE
# ==============================

echo "[4/5] Sauvegarde de sécurité du site actuel..."

SAFETY_ARCHIVE="wordpress_avant_restauration_$(date +%Y-%m-%d_%H-%M-%S).tar.gz"

tar -czpf "$TMP_DIR/$SAFETY_ARCHIVE" -C "$WEB_DIR" .

scp -P "$SSH_PORT" -i "$SSH_KEY" \
    -o BatchMode=yes \
    "$TMP_DIR/$SAFETY_ARCHIVE" \
    "${REMOTE}:${REMOTE_DIR}/${SAFETY_ARCHIVE}"

# ==============================
# RESTAURATION
# ==============================

echo "[5/5] Restauration en cours..."

touch "$MAINTENANCE"

rsync -aHAX --numeric-ids --delete \
    "$TMP_DIR/extracted/" \
    "$WEB_DIR/"

rm -f "$MAINTENANCE"

echo
echo "=================================="
echo " RESTAURATION TERMINEE"
echo " Archive : $ARCHIVE"
echo " Répertoire : $WEB_DIR"
echo "=================================="
echo
echo "Sauvegarde de sécurité :"
echo "$SAFETY_ARCHIVE"
