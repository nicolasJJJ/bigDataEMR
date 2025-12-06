import os
import json
import logging
from pathlib import Path

import boto3
from botocore.exceptions import ClientError
import sys

FILE_JSONL = "00.jsonl"
BUCKET_NAME = "sparkresultsjjjmain"          # <<< NOM du bucket, PAS l'ARN
S3_KEY = f"the-pile/bronze/{FILE_JSONL}"  # chemin (key) côté S3

KAGGLE_DATA_URL = "https://www.kaggle.com/datasets/dschettler8845/the-pile-dataset-part-00-of-29"


#aws & kaggle credentials

session = boto3.Session(region_name="eu-west-3")
ssm = session.client("ssm")

usr_value = ssm.get_parameter(Name="/kaggle/username", WithDecryption=True)["Parameter"]["Value"]
key_value = ssm.get_parameter(Name="/kaggle/key", WithDecryption=True)["Parameter"]["Value"]


################### kaggle credentials

kaggle_file = Path(__file__).parent.resolve() / "kaggle.json"
with kaggle_file.open("w") as f:
    json.dump({"username": usr_value, "key": key_value}, f)
try:
    os.chmod(kaggle_file, 0o600)
except Exception:
    pass

os.environ["KAGGLE_CONFIG_DIR"] = str(kaggle_file)

os.environ["KAGGLE_USERNAME"] = usr_value
os.environ["KAGGLE_KEY"] = key_value

#debug
# print("KAGGLE_USERNAME seen:", os.getenv("KAGGLE_USERNAME"))
# print("KAGGLE_CONFIG_DIR:", os.getenv("KAGGLE_CONFIG_DIR"))


import opendatasets as od

download_root = od.download(KAGGLE_DATA_URL)

if download_root is None:
    download_root = "the-pile-dataset-part-00-of-29"
    
download_root = Path(download_root).resolve()
print("Download dir:", download_root)


jsonl_file = next(download_root.rglob("00.jsonl"), None)

if not jsonl_file:
    raise FileNotFoundError("File not found.")



s3_client = session.client("s3")
try:
    s3_client.upload_file(str(jsonl_file), BUCKET_NAME, S3_KEY)
    print(f"Upload OK -> s3://{BUCKET_NAME}/{S3_KEY}")
    sys.exit(0)
except ClientError as e:
    logging.error("Échec upload S3: %s", e)
    raise