#!/bin/bash
sudo pip3 install --upgrade boto3 opendatasets
sudo -u hadoop mkdir -p /home/.kaggle
sudo -u hadoop chmod 700 /home/.kaggle