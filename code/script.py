import json
from pathlib import Path
from pyspark.sql import SparkSession
import os

from pyspark.sql.functions import col, length, instr, when
import boto3

# Getting Kaggle credentials

session = boto3.Session(region_name='eu-west-3')
ssm = session.client('ssm')

response_usr = ssm.get_parameter(Name="/kaggle/username", WithDecryption=True)
response_key = ssm.get_parameter(Name="/kaggle/key", WithDecryption=True)

usr_value = response_usr['Parameter']['Value']
key_value = response_key['Parameter']['Value']


os.environ["KAGGLE_USERNAME"] = usr_value
os.environ["KAGGLE_KEY"] = key_value


with open("kaggle.json", "w") as file:
    json.dump({"username":"{usr_value}","key":"{key_value}"}, file)
os.chmod("kaggle.json", 0o700)

# initiate spark session to avoid timeout

spark = SparkSession.builder \
    .appName("EMR_spark") \
    .getOrCreate()

spark.sparkContext.setLogLevel("INFO")

# Downloading kaggle file

import opendatasets as od 

od.download("https://www.kaggle.com/datasets/dschettler8845/the-pile-dataset-part-00-of-29", Path.cwd())


file_path = (Path.cwd()/ "the-pile-dataset-part-00-of-29" / "00.jsonl").resolve()

if not os.path.exists(file_path):
    raise FileNotFoundError(f"fichier introuvable à {file_path}")

# Spark job



df = spark.read.json(file_path)
df.printSchema()
df.show()


df = df.filter(length(col("text")) > 100)\
    .filter(~instr(col("text"),'copyright') > 0)\
    .withColumn('set_name', col("meta.pile_set_name"))\
    .drop('meta')

df.write \
  .partitionBy("set_name") \
  .mode("overwrite") \
  .option("compression", "snappy") \
  .parquet("s3a://sparkresultsjjj/thepile_cleaned/")

spark.stop()