import duckdb
import os
import pyarrow.csv as pv
import pyarrow.parquet as pq
import pandas as pd
import numpy as np
#import opendatasets as od

#od.download(
#    "https://www.kaggle.com/datasets/dschettler8845/the-pile-dataset-part-00-of-29",
#    "../data"
#)


crime_path = os.path.join("..", "data", "00.jsonl")

df = pd.read_json(crime_path, lines=True, nrows=100000)


df = df[~(df['text'].fillna('').str.len() < 100)]
df = df[~df['text'].str.lower().str.contains('copyright', na=False)]

print(len(df))

#print(df['meta'].apply(lambda x: x.get("pile_set_name")).head(1))
df['set_name'] = df['meta'].apply(lambda x: x.get("pile_set_name"))
df = df.drop(columns =['meta'])

print(df.columns)

# result_crime = duckdb.sql(f"SELECT AREA NAME, count(*) FROM read_parquet('{crime_path}') group by LIMIT 1").show(max_width=25000)
#colonnes = conn.execute(f"describe crimes;").fetchall()
# print(colonnes)

#
#result_crime = conn.execute(f"""SELECT AREA_NAME, Vict_Descent, c FROM (
#    SELECT AREA_NAME, Vict_Descent, COUNT(*) AS c,
#           ROW_NUMBER() OVER (PARTITION BY AREA_NAME ORDER BY COUNT(*) DESC) AS rn
#    FROM crimes
#    GROUP BY AREA_NAME, Vict_Descent
#) AS sub
#WHERE rn = 1;
#;""").fetchall()


#print(result_crime)
#dov : https://data.lacity.org/Public-Safety/Crime-Data-from-2020-to-Present/2nrs-mtv8/about_data
