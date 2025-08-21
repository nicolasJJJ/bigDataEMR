#!/bin/bash
set -euo pipefail

# --- Config ---
export AWS_DEFAULT_REGION="eu-west-3"
DATA_DIR="/mnt/thepile"              # /mnt > /tmp pour éviter de remplir la racine
KAGGLE_USER_PARAM="/kaggle/username" # SSM params
KAGGLE_KEY_PARAM="/kaggle/key"
KAGGLE_DIR="/root/.kaggle"           # Bootstrap tourne en root
DATA_URL="https://www.kaggle.com/datasets/dschettler8845/the-pile-dataset-part-00-of-29"
DATA_SUBDIR="the-pile-dataset-part-00-of-29"
LOCAL_JSONL="${DATA_DIR}/${DATA_SUBDIR}/00.jsonl"
HDFS_DEST="/data/thepile_raw"

# Ne tourner que sur le master
if ! grep -q '"isMaster": true' /mnt/var/lib/info/instance.json; then
  exit 0
fi

# Dépendances
command -v unzip >/dev/null 2>&1 || sudo yum -y install unzip || sudo dnf -y install unzip || true
python3 -m pip install --upgrade --quiet pip
python3 -m pip install --quiet kaggle opendatasets boto3

# Récup des creds Kaggle depuis SSM
KAGGLE_USERNAME="$(aws ssm get-parameter --name "${KAGGLE_USER_PARAM}" --with-decryption --query Parameter.Value --output text)"
KAGGLE_KEY="$(aws ssm get-parameter --name "${KAGGLE_KEY_PARAM}" --with-decryption --query Parameter.Value --output text)"

# Écriture config Kaggle là où il faut
mkdir -p "${KAGGLE_DIR}"
cat > "${KAGGLE_DIR}/kaggle.json" <<EOF
{"username":"${KAGGLE_USERNAME}","key":"${KAGGLE_KEY}"}
EOF
chmod 600 "${KAGGLE_DIR}/kaggle.json"
export KAGGLE_CONFIG_DIR="${KAGGLE_DIR}"
export KAGGLE_USERNAME KAGGLE_KEY

# Téléchargement dataset (opendatasets dézippe par défaut)
mkdir -p "${DATA_DIR}"
python3 - <<'PY'
import opendatasets as od, os
od.download(os.environ["DATA_URL"], data_dir=os.environ["DATA_DIR"])
PY

# Si jamais Kaggle a filé un zip et pas d'extract, on gère
ZIPFILE=$(ls "${DATA_DIR}/${DATA_SUBDIR}"/*.zip 2>/dev/null || true)
if [[ -n "${ZIPFILE}" && ! -f "${LOCAL_JSONL}" ]]; then
  echo "Décompression : ${ZIPFILE}"
  unzip -o "${ZIPFILE}" -d "${DATA_DIR}/${DATA_SUBDIR}"
fi

# Sanity check
if [[ ! -f "${LOCAL_JSONL}" ]]; then
  echo "Fichier introuvable : ${LOCAL_JSONL}" >&2
  exit 1
fi

# Création destination HDFS
# (certains clusters utilisent hdfs, d'autres hadoop; on tente hadoop d'abord)
if sudo -u hadoop hdfs dfs -test -d / 2>/dev/null; then HDFS_USER=hadoop; else HDFS_USER=hdfs; fi
sudo -u "${HDFS_USER}" hdfs dfs -mkdir -p "${HDFS_DEST}"

# Ingestion HDFS avec réplication 1 pour économiser l’espace
sudo -u "${HDFS_USER}" hdfs dfs -D dfs.replication=1 -put -f "${LOCAL_JSONL}" "${HDFS_DEST}/00.jsonl"
sudo -u "${HDFS_USER}" hdfs dfs -setrep -w 1 "${HDFS_DEST}/00.jsonl"

echo "OK"
