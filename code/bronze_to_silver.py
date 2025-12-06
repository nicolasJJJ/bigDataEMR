from pyspark.sql import SparkSession
from pyspark.sql.types import StructType, StructField, StringType


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

df = spark.read.schema(schema_parquet).json("s3://sparkresultsjjjmain/the-pile/bronze/00.jsonl")
resultat = df.write.mode("overwrite").parquet("s3://sparkresultsjjjmain/silver/00.parquet")
