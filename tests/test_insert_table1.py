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