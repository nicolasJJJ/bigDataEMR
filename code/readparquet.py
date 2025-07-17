import duckdb
import os
import pyarrow.csv as pv
import pyarrow.parquet as pq


crime_path = os.path.join("..", "data", "Crime_Data_from_2020_to_Present.parquet")

conn = duckdb.connect()

# Enregistrer la table dans duckBD
conn.execute(f"CREATE TABLE crimes AS SELECT * FROM read_parquet('{crime_path}')")

# Récupérer les colonnes
columns = conn.execute("PRAGMA table_info('crimes')").fetchall()

# Fabriquer les nouveaux noms de colonnes
rename_statements = []
for col in columns:
    old_name = col[1]
    new_name = old_name.replace(" ", "_")
    if old_name != new_name:
        rename_statements.append(f'RENAME COLUMN "{old_name}" TO "{new_name}"')

# Exécuter les renommages
for stmt in rename_statements:
    conn.execute(f'ALTER TABLE crimes {stmt}')


# result_crime = duckdb.sql(f"SELECT AREA NAME, count(*) FROM read_parquet('{crime_path}') group by LIMIT 1").show(max_width=25000)
colonnes = conn.execute(f"describe crimes;").fetchall()
# print(colonnes)

#
result_crime = conn.execute(f"""SELECT AREA_NAME, Vict_Descent, c FROM (
    SELECT AREA_NAME, Vict_Descent, COUNT(*) AS c,
           ROW_NUMBER() OVER (PARTITION BY AREA_NAME ORDER BY COUNT(*) DESC) AS rn
    FROM crimes
    GROUP BY AREA_NAME, Vict_Descent
) AS sub
WHERE rn = 1;
;""").fetchall()


print(result_crime)
#dov : https://data.lacity.org/Public-Safety/Crime-Data-from-2020-to-Present/2nrs-mtv8/about_data
