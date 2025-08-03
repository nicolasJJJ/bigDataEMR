#!/bin/bash
sudo pip3 install --upgrade boto3 opendatasets
sudo -u hadoop mkdir -p /home/hadoop/.kaggle
sudo -u hadoop chmod 700 /home/hadoop/.kaggle