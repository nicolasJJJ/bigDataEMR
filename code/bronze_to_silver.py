from pathlib import Path
from pyspark.sql import SparkSession, DataFrame
import os
from pyspark.testing.utils import assertDataFrameEqual
from pyspark.sql.types import StructType, StructField, StringType, LongType
from pyspark.sql.functions import col, length, instr, when
from test_clean_df import transform_df


spark = SparkSession.builder \
    .appName("EMR_spark") \
    .getOrCreate()

schema_parquet = StructType([
    StructField("text", StringType(), True),
    StructField("meta", StructType([
        StructField("pile_set_name", StringType(), True)
    ]), True)
])


spark.sparkContext.setLogLevel("WARN")

df = spark.read.schema(schema_parquet).json("s3a://sparkresultsjjjmain/the-pile/bronze/00.jsonl")
resultat = df.write.mode("overwrite").parquet("s3a://sparkresultsjjjmain/silver/00.parquet")
