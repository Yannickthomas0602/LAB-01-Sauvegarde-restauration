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

# ==============================
# INITIALISATION
# ==============================

DATE=$(date +"%Y-%m-%d_%H-%M-%S")
ARCHIVE="wordpress_${DATE}.tar.gz"
TMP_ARCHIVE="/tmp/${ARCHIVE}"

SSH_OPTS=(-p "$SSH_PORT" -i "$SSH_KEY" -o BatchMode=yes)

echo "=================================="
echo " SAUVEGARDE WORDPRESS"
echo "=================================="

# Vérification
if [[ ! -d "$WEB_DIR" ]]; then
    echo "ERREUR : répertoire $WEB_DIR introuvable"
    exit 1
fi

# Création archive
echo "[1/3] Création de l'archive..."

tar -czpf "$TMP_ARCHIVE" -C "$WEB_DIR" .

# Création répertoire distant
echo "[2/3] Préparation du serveur distant..."

ssh "${SSH_OPTS[@]}" "${SSH_USER}@${SSH_HOST}" \
    "mkdir -p '$REMOTE_DIR'"

# Transfert
echo "[3/3] Transfert de l'archive..."

scp -P "$SSH_PORT" -i "$SSH_KEY" \
    -o BatchMode=yes \
    "$TMP_ARCHIVE" \
    "${SSH_USER}@${SSH_HOST}:${REMOTE_DIR}/${ARCHIVE}"

# Suppression locale
rm -f "$TMP_ARCHIVE"

echo "=================================="
echo " SAUVEGARDE TERMINEE"
echo " Archive : $ARCHIVE"
echo " Serveur : $SSH_HOST"
echo "=================================="
