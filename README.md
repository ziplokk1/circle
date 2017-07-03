### The background...
I recently found myself with a need to create a tool which needed python and mysql together. I tried a ton of different methods even going so far as to write my own docker image which had python and mysql on the same image. But this was just too much overhead for my liking. Now, maybe there is already an image out there which encompasses my needs, but what if I need to use a different python or mysql version?

Needless to say, after pulling a lot of hairs, I finally found a way to get them to work together, albeit a bit hacky, and thought that I'd share my findings here.

### The issue... 

* While both dockers containers can be run in tandem, the mysql container will be available before any scripts contained in `/docker-entrypoint-initdb.d/` have finished running.
* This can lead to errors when testing because the tables that the tests are expecting have actually not been created yet and any other start up scripts contained in that folder may not have run.

### The solution...

* Call any setup scripts from the primary docker container.

### The code....

Lets go ahead and set up the containers. Obviously for my purposes I needed to use Python with MySql.
```yaml
version: 2
jobs:
  build:
    working_directory: ~/project_directory
    docker:
      - image: python:3.4
      - image: mysql:5.6
        environment:
          MYSQL_ROOT_PASSWORD: rootpass
          MYSQL_DATABASE: testdb
          MYSQL_USER: user
          MYSQL_PASSWORD: pass
```

The full list of environment variables for the mysql container can be found [at the mysql docker image page](https://hub.docker.com/_/mysql/).

Now we can go ahead and start setting up the steps required to allow our python container to communicate with the mysql container. This involves setting up mysql-client on our primary image.

```yaml
version: 2
jobs:
  build:
    [previous config here...]
    steps:
      - checkout
      - run:
          name: Configure MySQL GPG Keys
          command: |
            key='A4A9406876FCBD3C456770C88C718D3B5072E1F5'; \
            export GNUPGHOME="$(mktemp -d)"; \
            gpg --keyserver ha.pool.sks-keyservers.net --recv-keys "$key"; \
            gpg --export "$key" > /etc/apt/trusted.gpg.d/mysql.gpg; \
            rm -r "$GNUPGHOME"; \
            apt-key list > /dev/null
      - run:
          name: Install MySQL Client
          command: |
            apt-get update; \
            apt-get install -y mysql-client libmysqlclient-dev --no-install-recommends; \
            rm -rf /var/lib/apt/lists/*
```

So the thing with that first run command is that [it's shamelessly stolen from the MySQL Dockerfile](https://github.com/docker-library/mysql/blob/2bbab7b691b582e2df99dbd16525608adbff016e/5.6/Dockerfile). I just wanted to give credit to the original authors.

With the second run command, you may not need to install the `libmysqlclient-dev` library. But I installed it just to be safe since I've needed it for every python script using the `mysqlclient` and `sqlalchemy` libraries.

The thing to remember here is that the mysql container can be accessed from `127.0.0.1` for this example. Your mileage may vary especially if using multiple docker images. 

### Here is where things get a bit hacky...
The rest of this tutorial assumes that you're using a directory tree shown below

```
.
└── circle.yml
```

With the MySQL docker image, it will automatically run scripts placed in `/docker-entrypoint-initdb.d/` BUT since we don't really have the option of `docker cp` without having a container which supports docker (yes there is the `setup_remote_docker` command, but again, that's too much overhead for me) then we need to store our files with our program in a folder which (in this example has been called ./sql/).

Remember how I said previously that the primary container's steps can be executed before mysql fully boots up? Well if you run everything so far in circle CI that's exactly what is going to happen. You can try it yourself by adding the following to your `circle.yml`...

```yaml
version: 2
jobs:
  build:
    [previous config here...]
    steps:
      [previous steps here...]
      - run:
          name: Connect To MySQL Server
          command: |
            mysql -h 127.0.0.1 -u user -ppass -e "SHOW TABLES;" testdb
```

Will give you this error.

```
ERROR 2003 (HY000): Can't connect to MySQL server on '127.0.0.1' (111)
Exited with code 1
```

The solution that I've found is to make a shell script which attempts to execute that query every second until the process exits with a status of `0`.

### Wait for MySQL to finish booting up:

In your root directory make a file called `waitformysql.sh` and copy/paste the following into it.

```bash
#!/bin/bash

# How long to wait before finally deciding that mysql isn't going to boot.
MYSQL_BOOT_WAIT_TIMEOUT=30

MYSQL_USER=user
MYSQL_PASS=pass
MYSQL_DB=testdb
MYSQL_HOST=127.0.0.1

# Get the exit code from attempting to show tables in our database.
function mysqlRunning() {
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
```

Your directory tree should now look like this...

```
.
├── circle.yml
└── waitformysql.sh
```

Add `waitformysql.sh` to `circle.yml`.

```yaml
version: 2
jobs:
  build:
    [previous config here...]
    steps:
      [previous steps here...]
      - run:
          name: Wait For MySQL
          command |
            /bin/bash ./waitformysql.sh
```

Test it...

```
waiting for mysql..mysql running
```

And success!

### Run .sql Scripts:

Similar to the steps outlined above, we are going to make a file called `applysql.sh` in our root directory.

```bash
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
```

Make a folder in your project root directory called `sql`. This is where you will put all the .sql files needed for your database.

```
.
├── applysql.sh
├── circle.yml
├── sql
└── waitformysql.sh
```

Once you have the directory add a couple .sql files in it. For this purpose they are colloquially called `create_table_1.sql` and `create_table_2.sql`.

`create_table_1.sql`

```mysql
CREATE TABLE table_1 (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  some_field VARCHAR(15)
);
```

`create_table_2.sql`

```mysql
CREATE TABLE table_2 (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  some_field VARCHAR(15)
);
```

And the structure should look like this.

```
.
├── applysql.sh
├── circle.yml
├── sql
│   ├── create_table_1.sql
│   └── create_table_2.sql
└── waitformysql.sh
```

Add the following run command to your `steps` key in `circle.yml`:

```yaml
version: 2
jobs:
  build:
    [previous config here...]
    steps:
      [previous steps here...]
      - run:
          name: Execute SQL Scripts
          command: |
            /bin/bash ./applysql.sh
```

The output should look like this:

```
Processing ./sql/create_table_1.sql...
Processing ./sql/create_table_2.sql...
+------------------+
| Tables_in_testdb |
+------------------+
| table_1          |
| table_2          |
+------------------+
```

Success!

### Making python tests:

The following steps assume you're using sqlalchemy, mysqlclient, and nose, and that you've used `pip freeze > requirements.txt`.

Create a folder called `tests` and add a file named `test_insert_table1.py` in it.

Copy and paste the following into `test_insert_table1.py`:

```python
from contextlib import closing
import unittest

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker


class TestTable1Insert(unittest.TestCase):
    
    def setUp(self):
        engine = create_engine('mysql://127.0.0.1/testdb', connect_args={'user': 'user', 'passwd': 'pass'})
        self.Session = sessionmaker(engine)
        with closing(self.Session()) as s:
            s.execute("INSERT INTO table_1 (some_field) VALUES (:some_field);", {'some_field': 'hello world'})
            s.commit()
            
    def testInsert(self):
        with closing(self.Session()) as s:
            rows = s.execute("SELECT * FROM table_1;").fetchall()
        row = rows[0]
        self.assertEqual(row.id, 1)
        self.assertEqual(row.some_field, 'hello world')
        
    def tearDown(self):
        with closing(self.Session()) as s:
            s.execute("TRUNCATE table_1;")
```

Now your folder structure should look like this:

```
.
├── applysql.sh
├── circle.yml
├── requirements.txt
├── sql
│   ├── create_table_1.sql
│   └── create_table_2.sql
├── tests
│   └── test_insert_table1.py
└── waitformysql.sh
```

Update your `circle.yml` file to install the project dependencies and run the tests. For this example I'm using `nose` to run our unit tests.

```yaml
version: 2
jobs:
  build:
    [previous config here...]
    steps:
      [previous steps here...]
      - run:
          name: Install Requirements
          command: |
            pip install -r ./requirements.txt
      - run:
          name: Nosetests
          command: |
            nosetests -v
```

If everything went right, your output should look like this:

```
testInsert (test_insert_table1.TestTable1Insert) ... ok

----------------------------------------------------------------------
Ran 1 test in 0.252s

OK
```

Congrats! That's all there is to it!