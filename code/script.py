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

    # L'API FileSystem d'Hadoop n'existe pas nativement en Python
    # Il faut l'invoquer via la passerelle JVM (Py4J) de Spark
    URI = spark._jvm.java.net.URI
    HadoopPath = spark._jvm.org.apache.hadoop.fs.Path
    FileSystem = spark._jvm.org.apache.hadoop.fs.FileSystem
    conf = spark.sparkContext._jsc.hadoopConfiguration()
    
    fs = FileSystem.get(URI(path), conf)
    size_bytes = fs.getContentSummary(HadoopPath(path)).getLength()

    target_size_mb = 128
    num_partitions = max(1, int(size_bytes / (1024 * 1024 * target_size_mb)))

    df = transform_df(df)


    df.write \
        .repartition(num_partitions) \
        .mode("overwrite") \
        .option("compression", "snappy") \
        .parquet("s3://sparkresultsjjjmain/gold/thepile/")


    spark.stop()


