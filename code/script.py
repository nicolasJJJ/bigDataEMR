from pyspark.sql import SparkSession, DataFrame
import os

from pyspark.sql.functions import col, length
from pyspark.sql.types import StructType, StructField, StringType, LongType

schema_parquet = StructType([
    StructField("text", StringType(), True),
    StructField("meta", StructType([
        StructField("pile_set_name", StringType(), True)
    ]), True)
])

path = "s3://sparkresultsjjjmain/silver/00.parquet"

def transform_df(df: DataFrame) -> DataFrame:
    df = df.filter(length(col("text")) > 100)\
       .where(~col('text').contains('copyright'))\
       .withColumn('set_name', col("meta.pile_set_name"))\
       .drop('meta')
    return df

if __name__ == "__main__":
    spark = SparkSession.builder \
        .appName("EMR_spark") \
        .getOrCreate()

    spark.sparkContext.setLogLevel("WARN")

    df = spark.read.parquet(path)

    size_bytes = df._jdf.queryExecution().optimizedPlan().stats().sizeInBytes()


    target_size_mb = 128
    num_partitions = max(1, int(size_bytes / (1024 * 1024 * target_size_mb)))

    df = transform_df(df)


    df.write \
        .repartition(num_partitions) \
        .mode("overwrite") \
        .option("compression", "snappy") \
        .parquet("s3://sparkresultsjjjmain/gold/thepile/")


    spark.stop()


