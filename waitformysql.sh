#!/bin/bash

function mysqlRunning() { \
  mysql -h 127.0.0.1 -u user -ppass -e "SHOW TABLES;" testdb > /dev/null 2>&1
  echo $?
};
printf "waiting for mysql"
while true
do
    if [[ $(mysqlRunning) == 1 ]]
    then
      printf "."
      sleep 1
    else
      echo "mysql running"
      break
    fi
done