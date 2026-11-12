# Sauvegarde et restauration WordPress

Ce dossier contient deux méthodes pour sauvegarder et restaurer les fichiers
d'un site WordPress :

- **méthode simple** : stockage sur un serveur distant via SSH/SCP ;
- **méthode S3** : stockage dans un bucket compatible S3, ici MinIO.

Les scripts archivent le contenu de `/var/www/html`. Ils ne sauvegardent pas
la base de données WordPress. Pour une restauration complète du site, la base
de données doit donc être sauvegardée et restaurée séparément.

## Fichiers

| Fichier | Fonction |
|---|---|
| `backup_wordpress.sh` | Crée une archive et l'envoie sur le serveur distant |
| `restore_wordpress.sh` | Liste et restaure une archive depuis le serveur distant |
| `backup_S3.sh` | Crée une archive et l'envoie dans MinIO/S3 |
| `restore_S3.sh` | Liste et restaure une archive depuis MinIO/S3 |

## Fonctionnement commun

### Sauvegarde

1. Le script vérifie que `/var/www/html` existe (les scripts de restauration
   et les scripts S3 exigent également une exécution en `root`).
2. Le contenu du répertoire est compressé dans une archive `tar.gz`.
3. L'archive est envoyée vers le stockage choisi.
4. Les fichiers temporaires locaux sont supprimés automatiquement.

Le nom d'une archive classique est :

```text
wordpress_YYYY-MM-DD_HH-MM-SS.tar.gz
```

### Restauration

1. Les archives disponibles sont affichées et l'opérateur en sélectionne une.
2. Une confirmation explicite (`oui`) est demandée.
3. L'archive est téléchargée puis vérifiée.
4. Les chemins absolus et les chemins contenant `..` sont refusés.
5. L'archive est extraite dans un répertoire temporaire.
6. Une sauvegarde de sécurité du site actuel est créée et stockée au même endroit.
7. Le contenu de `/var/www/html` est remplacé avec `rsync --delete`.
8. Le fichier `.maintenance` est utilisé pendant le remplacement du site.

La restauration est destructive : les fichiers présents dans
`/var/www/html` mais absents de l'archive sont supprimés. La sauvegarde de
sécurité permet de revenir à l'état précédent.

## Méthode simple : SSH/SCP

### Configuration

Les paramètres sont définis directement dans
[`backup_wordpress.sh`](C:/Users/yanni/Desktop/Sauvegarde-Restauration/backup_wordpress.sh)
et [`restore_wordpress.sh`](C:/Users/yanni/Desktop/Sauvegarde-Restauration/restore_wordpress.sh) :

```bash
WEB_DIR="/var/www/html"
SSH_USER="yannick"
SSH_HOST="192.168.137.61"
SSH_PORT="2224"
REMOTE_DIR="/home/yannick/backups/wordpress"
SSH_KEY="/root/.ssh/wordpress_backup"
```

À adapter selon l'environnement :

- `SSH_HOST` et `SSH_PORT` : serveur distant ;
- `SSH_USER` : utilisateur SSH ;
- `REMOTE_DIR` : répertoire de stockage distant ;
- `SSH_KEY` : clé privée utilisée sans saisie interactive.

La clé doit permettre une connexion SSH en mode non interactif (`BatchMode`).
Le répertoire distant est créé automatiquement lors d'une sauvegarde.

### Dépendances

La sauvegarde utilise `tar`, `ssh` et `scp`. La restauration utilise en plus
`rsync` et `awk`.

### Utilisation

Depuis le serveur WordPress :

```bash
sudo bash backup_wordpress.sh
sudo bash restore_wordpress.sh
```

La sauvegarde est envoyée sur le serveur SSH. La restauration récupère une
archive depuis ce serveur et y dépose également la sauvegarde de sécurité
créée avant le remplacement.

## Méthode S3 avec MinIO

### Configuration

Les scripts lisent le fichier :

```text
/root/.config/wordpress-minio.env
```

Exemple de contenu :

```bash
S3_ENDPOINT="https://minio.example.local"
S3_BUCKET="wordpress-backups"
S3_PREFIX="wordpress"
AWS_ACCESS_KEY_ID="votre-identifiant"
AWS_SECRET_ACCESS_KEY="votre-secret"
AWS_DEFAULT_REGION="us-east-1"
```

Les variables obligatoires sont `S3_ENDPOINT`, `S3_BUCKET`,
`AWS_ACCESS_KEY_ID` et `AWS_SECRET_ACCESS_KEY`. `AWS_DEFAULT_REGION` est
facultative et vaut `us-east-1` par défaut. `S3_PREFIX` est facultative ; les
slashs au début et à la fin sont normalisés par les scripts.

Le fichier contient un secret et doit être protégé :

```bash
sudo chown root:root /root/.config/wordpress-minio.env
sudo chmod 600 /root/.config/wordpress-minio.env
```

### Dépendances

La méthode S3 nécessite :

- le client AWS CLI (`aws`) ;
- `tar` pour créer et vérifier les archives ;
- `rsync`, `awk`, `sort` et `grep` pour la restauration.

Le client AWS CLI est utilisé avec `--endpoint-url "$S3_ENDPOINT"` afin de
cibler MinIO plutôt qu'AWS. Le bucket doit déjà exister et les identifiants
doivent autoriser sa lecture et son écriture.

### Utilisation

Depuis le serveur WordPress :

```bash
sudo bash backup_S3.sh
sudo bash restore_S3.sh
```

Les archives sont stockées dans :

```text
s3://S3_BUCKET/S3_PREFIX/
```

Lors d'une restauration, la sauvegarde de sécurité est également envoyée
dans ce même préfixe. Elle porte un nom de la forme
`safety_before_restore_YYYY-MM-DD_HH-MM-SS.tar.gz`.

## Différences entre les deux méthodes

| Point | Script simple | Script S3 |
|---|---|---|
| Stockage | Répertoire d'un serveur distant | Bucket MinIO/S3 |
| Transport | SSH et SCP | AWS CLI et API S3 |
| Authentification | Clé privée SSH | Clé d'accès et clé secrète S3 |
| Configuration | Valeurs dans les scripts | Fichier `.env` séparé |
| Dépendances spécifiques | `ssh`, `scp` | `aws` |
| Accès aux archives | Serveur SSH disponible | Endpoint MinIO et bucket accessibles |
| Sauvegarde de sécurité | Sur le serveur distant | Dans le bucket S3 |
| Évolutivité | Dépend d'un serveur et de son disque | Adaptée au stockage objet et à la réplication |

Le contenu restauré est équivalent dans les deux cas. Seul le moyen de
stockage et de transfert des archives change.

## Recommandations

- Tester régulièrement une restauration, pas seulement la création d'archives.
- Sauvegarder la base de données séparément.
- Ne pas placer les clés S3 ou la clé privée SSH dans un dépôt Git.
- Vérifier l'espace disponible sur le serveur distant ou les quotas du bucket.
- Conserver plusieurs versions d'archives et définir une politique de
  rétention.
- Vérifier les permissions WordPress après restauration si le site utilise des
  utilisateurs ou services différents.
