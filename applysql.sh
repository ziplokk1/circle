#!/bin/bash

SCRIPTS=./sql/*
MYSQL_USER=user
MYSQL_PASS=pass
MYSQL_DB=testdb
MYSQL_HOST=127.0.0.1

for f in ${SCRIPTS}
do
  echo "Processing ${f}..."
  mysql -h ${MYSQL_HOST} -u ${MYSQL_USER} -p${MYSQL_PASS} ${MYSQL_DB} < "${f}"
done
mysql -h ${MYSQL_HOST} -u ${MYSQL_USER} -p${MYSQL_PASS} -e "SHOW TABLES;" ${MYSQL_DB}