
import os
import sys


import pytest
from pyspark.sql import SparkSession, Row
from transform_df import transform_df

@pytest.fixture(scope="session")
def spark():

   
    spark = SparkSession.builder \
        .master("local[1]") \
        .appName("pytest-pyspark-local-testing") \
        .getOrCreate()
    yield spark
    spark.stop()

def test_transform_df(spark):


    data = [
        {"text": "i will talk about the bad salaries in France ! These crazy spookies tax you like never URSS did ! And you would agree to this ?", "meta": {"pile_set_name": "Pile-CC"}},
        {"text": "Stone Cold Steve Austin", "meta": {"pile_set_name": "Pile-CC"}},
        {"text": "The first thing I want to be done, is to get that piece of crap out of my ring. Don't just get him out of the ring, get him out of the WWF because I've proved son, without a shadow of a doubt, you ain't got what it takes anymore! You sit there and you thump your Bible, and you say your prayers, and it didn t get you anywhere. Talk about your psalms, talk about John 3:16… Austin 3:16 says I just whipped your ass! copyright WWE", "meta": {"pile_set_name": "Pile-CC"}}
    ]
    df = spark.createDataFrame(data)
        
    result = transform_df(df)


    #result.show()

    expected_data = [Row(text="i will talk about the bad salaries in France ! These crazy spookies tax you like never URSS did ! And you would agree to this ?", set_name="Pile-CC")]
    expected_df = spark.createDataFrame(expected_data)
    
    assert result.collect() == expected_df.collect(), "Chiottes"

