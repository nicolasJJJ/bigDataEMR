#!/bin/bash
set -euo pipefail

# --- Config ---
export AWS_DEFAULT_REGION="eu-west-3"
DATA_DIR="/mnt/thepile"
KAGGLE_USER_PARAM="/kaggle/username"
KAGGLE_KEY_PARAM="/kaggle/key"
DATA_URL="https://www.kaggle.com/datasets/dschettler8845/the-pile-dataset-part-00-of-29"
DATA_SUBDIR="the-pile-dataset-part-00-of-29"
HDFS_DEST="/data/thepile_raw"

# Ne tourner que sur le master
grep -q '"isMaster": true' /mnt/var/lib/info/instance.json || exit 0

# Qui suis-je ? (root en bootstrap, hadoop en step)
EMR_USER="$(id -un)"
EMR_HOME="$(getent passwd "$EMR_USER" | cut -d: -f6 || echo "/home/$EMR_USER")"
KAGGLE_DIR="${EMR_HOME}/.kaggle"
BIN_DIR="${EMR_HOME}/.local/bin"
export PATH="$PATH:${BIN_DIR}"

echo "[*] User: ${EMR_USER} | Home: ${EMR_HOME}"

# Dépendances
command -v unzip >/dev/null 2>&1 || sudo yum -y install unzip || sudo dnf -y install unzip || true

if [[ $EUID -eq 0 ]]; then
  # Install système si root
  python3 -m pip install --upgrade --quiet pip
  python3 -m pip install --quiet kaggle opendatasets boto3
else
  # Sinon install --user et on étend le PATH (déjà fait plus haut)
  python3 -m pip install --user --upgrade --quiet pip
  python3 -m pip install --user --quiet kaggle opendatasets boto3
fi

# Récup des creds Kaggle depuis SSM
KAGGLE_USERNAME="$(aws ssm get-parameter --name "${KAGGLE_USER_PARAM}" --with-decryption --query Parameter.Value --output text)"
KAGGLE_KEY="$(aws ssm get-parameter --name "${KAGGLE_KEY_PARAM}" --with-decryption --query Parameter.Value --output text)"
export KAGGLE_USERNAME KAGGLE_KEY

echo "[*] Kaggle"


# Écriture config Kaggle dans le home du user courant (PAS de redirection sudo !)
umask 077
mkdir -p "${KAGGLE_DIR}"
cat > "${KAGGLE_DIR}/kaggle.json" <<EOF
{"username":"${KAGGLE_USERNAME}","key":"${KAGGLE_KEY}"}
EOF
chmod 600 "${KAGGLE_DIR}/kaggle.json"
export KAGGLE_CONFIG_DIR="${KAGGLE_DIR}"

echo "[*] Configs"

# Téléchargement dataset (opendatasets dézippe par défaut)
mkdir -p "${DATA_DIR}"
python3 - <<'PY'
import os, opendatasets as od
od.download(os.environ["DATA_URL"], data_dir=os.environ["DATA_DIR"])
PY

echo "[*] DLL"

LOCAL_JSONL="${DATA_DIR}/${DATA_SUBDIR}/00.jsonl"

# Si Kaggle a filé un zip et pas d'extract, on gère
ZIPFILE=$(ls "${DATA_DIR}/${DATA_SUBDIR}"/*.zip 2>/dev/null || true)
if [[ -n "${ZIPFILE}" && ! -f "${LOCAL_JSONL}" ]]; then
  echo "[*] Décompression : ${ZIPFILE}"
  unzip -o "${ZIPFILE}" -d "${DATA_DIR}/${DATA_SUBDIR}"
fi

# Sanity check
if [[ ! -f "${LOCAL_JSONL}" ]]; then
  echo "[!] Fichier introuvable : ${LOCAL_JSONL}" >&2
  echo "    (Vérifie que tu as accepté les ToS du dataset sur Kaggle si 403)"
  exit 1
fi

# Choix user HDFS
if sudo -u hadoop hdfs dfs -test -d / 2>/dev/null; then HDFS_USER=hadoop; else HDFS_USER=hdfs; fi
sudo -u "${HDFS_USER}" hdfs dfs -mkdir -p "${HDFS_DEST}"

# Ingestion HDFS avec réplication 1
sudo -u "${HDFS_USER}" hdfs dfs -D dfs.replication=1 -put -f "${LOCAL_JSONL}" "${HDFS_DEST}/00.jsonl"
sudo -u "${HDFS_USER}" hdfs dfs -setrep -w 1 "${HDFS_DEST}/00.jsonl"

echo "[OK] hdfs://${HDFS_DEST}/00.jsonl"
