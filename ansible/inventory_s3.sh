#!/usr/bin/env bash
aws s3 cp s3://itschool-s3/inventory.ini inventory.ini --region eu-north-1 >/dev/null
cat inventory.ini