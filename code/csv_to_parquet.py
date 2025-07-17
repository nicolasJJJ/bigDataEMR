import pyarrow.csv as pv
import pyarrow.parquet as pq
import os


inputdir = 'C:\\Users\\warcrime\\git\\bigDataEMR\\data\\input'

for filename in os.listdir(inputdir):
    filepath  = inputdir + "\\" + filename
    print(inputdir + "\\" + filename)
    table = pv.read_csv(filepath)
    pq.write_table(table, filepath.replace('csv', 'parquet'))
