from pathlib import Path
from pyspark.sql import SparkSession, DataFrame
import os
from pyspark.testing.utils import assertDataFrameEqual

from pyspark.sql.functions import col, length, instr, when
from test_clean_df import transform_df


spark = SparkSession.builder \
    .appName("EMR_spark") \
    .getOrCreate()

spark.sparkContext.setLogLevel("WARN")

df = spark.read.load("s3a://sparkresultsjjjmain/the-pile/part-00/00.parquet")

df = transform_df(df)

df.write \
  .partitionBy("set_name") \
  .mode("overwrite") \
  .option("compression", "snappy") \
  .parquet("s3a://sparkresultsjjj/thepile_cleaned/")

spark.stop()




