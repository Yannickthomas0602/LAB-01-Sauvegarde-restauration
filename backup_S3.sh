
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
DATE=$(date +"%Y-%m-%d_%H-%M-%S")
ARCHIVE="wordpress_${DATE}.tar.gz"
TMP_ARCHIVE="${TMP_DIR}/${ARCHIVE}"

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# ==============================
# VERIFICATIONS
# ==============================

echo "=================================="
echo " SAUVEGARDE WORDPRESS - MINIO S3"
echo "=================================="

if [[ $EUID -ne 0 ]]; then
    echo "ERREUR : lancer ce script avec sudo ou en root."
    exit 1
fi

for CMD in aws tar; do
    command -v "$CMD" >/dev/null || {
        echo "ERREUR : commande manquante : $CMD"
        exit 1
    }
done

if [[ ! -d "$WEB_DIR" ]]; then
    echo "ERREUR : répertoire $WEB_DIR introuvable."
    exit 1
fi

# ==============================
# CREATION ARCHIVE
# ==============================

echo "[1/3] Création de l'archive..."

tar -czpf "$TMP_ARCHIVE" -C "$WEB_DIR" .

# ==============================
# VERIFICATION MINIO
# ==============================

echo "[2/3] Vérification de la connexion MinIO..."

aws --endpoint-url "$S3_ENDPOINT" \
    s3api head-bucket \
    --bucket "$S3_BUCKET" \
    --no-cli-pager

# ==============================
# ENVOI VERS MINIO
# ==============================

echo "[3/3] Envoi de la sauvegarde vers MinIO..."

aws --endpoint-url "$S3_ENDPOINT" \
    s3 cp "$TMP_ARCHIVE" "${S3_URI}${ARCHIVE}" \
    --only-show-errors \
    --no-cli-pager

# ==============================
# TERMINAISON
# ==============================

echo "=================================="
echo " SAUVEGARDE TERMINEE"
echo "=================================="
echo "Archive : $ARCHIVE"
echo "Bucket  : $S3_BUCKET"
echo "Prefixe : $S3_PREFIX"
echo "MinIO   : $S3_ENDPOINT"
echo "=================================="
