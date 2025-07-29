import json
from pyspark.sql import SparkSession
import os
import opendatasets as od
from pyspark.sql.functions import col, length, instr, when
import boto3

session = boto3.Session(region_name='eu-west-3')
ssm = session.client('ssm')

usr = ssm.get_parameter(Name="/kaggle/username", WithDecryption=True)
key = ssm.get_parameter(Name="/kaggle/key", WithDecryption=True)

kaggle_dir = os.path.expanduser("~/.kaggle")
os.makedirs(kaggle_dir, exist_ok=True)
kaggle_path = os.path.join(kaggle_dir, "kaggle.json")

with open(kaggle_path, "w") as json_file:
    json.dump({"username": usr, "key": key}, json_file)

os.chmod(kaggle_path, 0o600)

od.download(
    "https://www.kaggle.com/datasets/dschettler8845/the-pile-dataset-part-00-of-29",
    "../data"
)


file_path = os.path.abspath("../data/the-pile-dataset-part-00-of-29/00.jsonl")

if not os.path.exists(file_path):
    raise FileNotFoundError(f"fichier introuvable à {file_path}")


spark = SparkSession.builder \
    .appName("EMR_spark") \
    .getOrCreate()

spark.sparkContext.setLogLevel("WARN")


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