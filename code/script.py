from pathlib import Path
from pyspark.sql import SparkSession
import os

from pyspark.sql.functions import col, length, instr, when


# initiate spark session to avoid timeout

spark = SparkSession.builder \
    .appName("EMR_spark") \
    .getOrCreate()

spark.sparkContext.setLogLevel("WARN")


df = spark.read.json("hdfs:///data/thepile_raw/00.jsonl")
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