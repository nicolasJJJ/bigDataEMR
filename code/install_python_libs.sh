#!/bin/bash
set -euo pipefail

sudo pip3 install --upgrade boto3 opendatasets
sudo mkdir /home/.config
sudo chmod -R 766 /home/.config


# Ne tourner que sur le master
grep -q '"isMaster": true' /mnt/var/lib/info/instance.json ||  exit 0


# get SSM credentials
export AWS_DEFAULT_REGION=eu-west-3
KAGGLE_USERNAME=$(aws ssm get-parameter --name /kaggle/username --with-decryption --query Parameter.Value --output text)
KAGGLE_KEY=$(aws ssm get-parameter --name /kaggle/key --with-decryption --query Parameter.Value --output text)



cat > "kaggle.json" <<EOF
{"username":"$KAGGLE_USERNAME","key":"$KAGGLE_KEY"}
EOF
chmod 600 "kaggle.json"

# Télécharger le dataset avec opendatasets (dézippé par défaut)
DATA_DIR="/tmp/thepile"
python3 - <<PY
import opendatasets as od
from pathlib import Path
od.download("https://www.kaggle.com/datasets/dschettler8845/the-pile-dataset-part-00-of-29", Path("$DATA_DIR"))
PY

LOCAL_JSONL="$DATA_DIR/the-pile-dataset-part-00-of-29/00.jsonl"

ZIPFILE=$(ls "$DATA_DIR"/the-pile-dataset-part-00-of-29/*.zip 2>/dev/null || true)
if [[ -n "$ZIPFILE" && ! -f "$LOCAL_JSONL" ]]; then
  echo "Décompression de $ZIPFILE"
  unzip -o "$ZIPFILE" -d "$DATA_DIR/the-pile-dataset-part-00-of-29"
fi

if [[ ! -f "$LOCAL_JSONL" ]]; then
  echo "Fichier introuvable après download : $LOCAL_JSONL" >&2
  exit 1
fi

# Copier dans HDFS (répertoire cible)
HDFS_DEST="/data/thepile_raw"
sudo -u hadoop hdfs dfs -mkdir -p "$HDFS_DEST"

# Ingestion avec réplication à 1 pour pas exploser l'espace (tu peux ajuster après)
sudo -u hadoop hdfs dfs -D dfs.replication=1 -put -f "$LOCAL_JSONL" "$HDFS_DEST/00.jsonl"
sudo -u hadoop hdfs dfs -setrep -w 1 "$HDFS_DEST/00.jsonl"

echo "Téléchargement Kaggle et copie HDFS terminés : hdfs:///data/thepile_raw/00.jsonl"
