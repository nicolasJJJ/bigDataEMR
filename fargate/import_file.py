import os
import json
import logging
from pathlib import Path

import boto3
from botocore.exceptions import ClientError
import sys
import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq

FILE_PARQUET = "00.parquet"
BUCKET_NAME = "sparkresultsjjjmain"          # <<< NOM du bucket, PAS l'ARN
S3_KEY = f"the-pile/part-00/{FILE_PARQUET}"  # chemin (key) côté S3

KAGGLE_DATA_URL = "https://www.kaggle.com/datasets/dschettler8845/the-pile-dataset-part-00-of-29"


#aws & kaggle credentials

session = boto3.Session(region_name="eu-west-3")
ssm = session.client("ssm")

usr_value = ssm.get_parameter(Name="/kaggle/username", WithDecryption=True)["Parameter"]["Value"]
key_value = ssm.get_parameter(Name="/kaggle/key", WithDecryption=True)["Parameter"]["Value"]

CHUNK_ROWS = 25_000  

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


jsonl_files = list(download_root.rglob("00.jsonl"))

if not jsonl_files:
    raise FileNotFoundError("File not found.")



################### JSONL to Parquet 
writer = None
rows_total = 0
schema = None

try:
    for jsonl_path in jsonl_files:
        print(f"[Lecture streaming] {jsonl_path}")
        try:
            json_iter = pd.read_json(
                jsonl_path,
                lines=True,
                chunksize=CHUNK_ROWS,
                dtype_backend="pyarrow"  
            )
        except TypeError:
            #### if pandas < 2.0
            json_iter = pd.read_json(
                jsonl_path,
                lines=True,
                chunksize=CHUNK_ROWS
            )

        for i, chunk in enumerate(json_iter, start=1):
            table = pa.Table.from_pandas(chunk, preserve_index=False)

            if writer is None:
                schema = table.schema
                writer = pq.ParquetWriter(
                    FILE_PARQUET,
                    schema,
                    compression="snappy",
                    use_dictionary=True
                )

            if table.schema != schema:
                for name in schema.names:
                    if name not in table.schema.names:
                        table = table.append_column(name, pa.nulls(len(table)))
                table = table.select(schema.names)

            writer.write_table(table)  

            rows_total += table.num_rows
            if i % 10 == 0:
                print(f"  -> {rows_total:,} written rows")

finally:
    if writer is not None:
        writer.close()

print(f"Converted -> {FILE_PARQUET} ({rows_total:,} rows)")

################### to S3
print("S3")
s3_client = session.client("s3")
try:
    s3_client.upload_file(FILE_PARQUET, BUCKET_NAME, S3_KEY)
    print(f"Upload OK -> s3://{BUCKET_NAME}/{S3_KEY}")
    sys.exit(0)
except ClientError as e:
    logging.error("Échec upload S3: %s", e)
    raise