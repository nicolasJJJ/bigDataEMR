from pyspark.sql import SparkSession
import os
import opendatasets as od
from pyspark.sql.functions import col, length, instr, when


od.download(
    "https://www.kaggle.com/datasets/dschettler8845/the-pile-dataset-part-00-of-29",
    "../data"
)


file_path = os.path.abspath("../data/the-pile-dataset-part-00-of-29/00.jsonl")

if not os.path.exists(file_path):
    raise FileNotFoundError(f"PUTAIN DE MERDE : fichier introuvable à {file_path}")


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