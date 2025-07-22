from pyspark.sql import SparkSession
from pyspark.sql.functions import col
import os
import opendatasets as od

od.download(
    "https://www.kaggle.com/datasets/dschettler8845/the-pile-dataset-part-00-of-29",
    "../data"
)


file_path = os.path.abspath("../data/the-pile-dataset-part-00-of-29/00.jsonl")

if not os.path.exists(file_path):
    raise FileNotFoundError(f"PUTAIN DE MERDE : fichier introuvable à {file_path}")


# Création d'une session Spark en local
spark = SparkSession.builder \
    .appName("TestLocal") \
    .master("local[*]") \
    .getOrCreate()


df = spark.read.json(file_path)
df.printSchema()
df.show()

spark.stop()