#!/bin/bash

MYSQL_BOOT_WAIT_TIMEOUT=30
MYSQL_USER=user
MYSQL_PASS=pass
MYSQL_DB=testdb
MYSQL_HOST=127.0.0.1

function mysqlRunning() {
  # Make sure that user, pass, and testdb are stored somewhere else such as env variables.
  mysql -h ${MYSQL_HOST} -u ${MYSQL_USER} -p${MYSQL_PASS} -e "SHOW TABLES;" ${MYSQL_DB} > /dev/null 2>&1
  echo $?
};

printf "waiting for mysql"
for i in $(seq 0 ${MYSQL_BOOT_WAIT_TIMEOUT})
do
    if [[ $(mysqlRunning) -eq 1 ]]
    then
      printf "."
      if [[ ${i} -eq ${MYSQL_BOOT_WAIT_TIMEOUT} ]]
      then
        echo "mysql boot timeout"
        exit 1
      fi
      sleep 1
    else
      echo "mysql running"
      break
    fi
done