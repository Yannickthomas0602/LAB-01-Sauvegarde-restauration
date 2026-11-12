
#!/usr/bin/env bash
set -Eeuo pipefail

# ==============================
# CONFIGURATION
# ==============================

WEB_DIR="/var/www/html"
ENV_FILE="/root/.config/wordpress-minio.env"

# ==============================
# INITIALISATION
# ==============================

if [[ ! -f "$ENV_FILE" ]]; then
    echo "ERREUR : fichier de configuration MinIO introuvable."
    exit 1
fi

source "$ENV_FILE"

: "${S3_ENDPOINT:?S3_ENDPOINT manquant}"
: "${S3_BUCKET:?S3_BUCKET manquant}"
: "${AWS_ACCESS_KEY_ID:?AWS_ACCESS_KEY_ID manquant}"
: "${AWS_SECRET_ACCESS_KEY:?AWS_SECRET_ACCESS_KEY manquant}"

export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
export AWS_EC2_METADATA_DISABLED=true

S3_PREFIX="${S3_PREFIX#/}"
S3_PREFIX="${S3_PREFIX%/}"

S3_URI="s3://${S3_BUCKET}/${S3_PREFIX:+${S3_PREFIX}/}"

TMP_DIR=$(mktemp -d)
MAINTENANCE="$WEB_DIR/.maintenance"
MAINTENANCE_CREATED=false

cleanup() {
    rm -rf "$TMP_DIR"

    if [[ "$MAINTENANCE_CREATED" == true ]]; then
        rm -f "$MAINTENANCE"
    fi
}

trap cleanup EXIT

# ==============================
# VERIFICATIONS
# ==============================

if [[ $EUID -ne 0 ]]; then
    echo "ERREUR : lancer ce script avec sudo ou en root."
    exit 1
fi

for CMD in aws tar rsync awk sort grep; do
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
echo " RESTAURATION WORDPRESS - MINIO S3"
echo "=================================="

# ==============================
# CONNEXION MINIO
# ==============================

echo "Vérification de la connexion MinIO..."

aws --endpoint-url "$S3_ENDPOINT" \
    s3api head-bucket \
    --bucket "$S3_BUCKET" \
    --no-cli-pager

# ==============================
# LISTE DES ARCHIVES
# ==============================

echo
echo "Recherche des sauvegardes MinIO..."

LIST=$(
    aws --endpoint-url "$S3_ENDPOINT" \
        s3 ls "$S3_URI" \
        --no-cli-pager |
    awk '$4 ~ /^wordpress_[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}\.tar\.gz$/ {print $4}' |
    sort -r
)

if [[ -z "$LIST" ]]; then
    echo "Aucune archive disponible dans MinIO."
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
echo "[1/5] Téléchargement depuis MinIO..."

aws --endpoint-url "$S3_ENDPOINT" \
    s3 cp "${S3_URI}${ARCHIVE}" "$TMP_DIR/$ARCHIVE" \
    --only-show-errors \
    --no-cli-pager

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

SAFETY_ARCHIVE="safety_before_restore_$(date +%Y-%m-%d_%H-%M-%S).tar.gz"

tar -czpf "$TMP_DIR/$SAFETY_ARCHIVE" -C "$WEB_DIR" .

echo "Envoi de la sauvegarde de sécurité vers MinIO..."

aws --endpoint-url "$S3_ENDPOINT" \
    s3 cp "$TMP_DIR/$SAFETY_ARCHIVE" "${S3_URI}${SAFETY_ARCHIVE}" \
    --only-show-errors \
    --no-cli-pager

# ==============================
# RESTAURATION
# ==============================

echo "[5/5] Restauration en cours..."

touch "$MAINTENANCE"
MAINTENANCE_CREATED=true

rsync -aHAX --numeric-ids --delete \
    --exclude='/.maintenance' \
    "$TMP_DIR/extracted/" \
    "$WEB_DIR/"

# ==============================
# TERMINAISON
# ==============================

rm -f "$MAINTENANCE"
MAINTENANCE_CREATED=false

echo
echo "=================================="
echo " RESTAURATION TERMINEE"
echo "=================================="
echo "Archive       : $ARCHIVE"
echo "Bucket        : $S3_BUCKET"
echo "Répertoire    : $WEB_DIR"
echo "=================================="

echo
echo "Sauvegarde de sécurité :"
echo "$SAFETY_ARCHIVE"
