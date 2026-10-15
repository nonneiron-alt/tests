"""Export only the application's two tables for one-time SQLite -> D1 import."""
import sqlite3
import sys
from pathlib import Path

def literal(value):
    if value is None:
        return 'NULL'
    if isinstance(value, (int, float)):
        return str(value)
    return "'" + str(value).replace("'", "''") + "'"

source = Path(sys.argv[1] if len(sys.argv) > 1 else 'quizzes.sqlite3')
target = Path(sys.argv[2] if len(sys.argv) > 2 else '.deploy/import.sql')
# Open read-only: don't create an empty DB if the path is wrong.
connection = sqlite3.connect(source.resolve().as_uri() + '?mode=ro', uri=True)
target.parent.mkdir(parents=True, exist_ok=True)
with target.open('w', encoding='utf-8', newline='\n') as output:
    output.write('-- One-time import from local SQLite. Contains saved results. Keep private.\n')
    # OR IGNORE preserves existing cloud data on later deployments.
    for table, columns in [
        ('quizzes', ['id', 'title', 'emoji', 'category', 'description', 'image', 'plays', 'created']),
        ('sessions', ['id', 'quiz_id', 'history', 'result']),
    ]:
        column_sql = ','.join(columns)
        for row in connection.execute(f'SELECT {column_sql} FROM {table}'):
            statement = f'INSERT INTO {table}({column_sql}) VALUES(' + ','.join(map(literal, row)) + ')'
            if table == 'quizzes':
                statement += ' ON CONFLICT(id) DO UPDATE SET plays=MAX(quizzes.plays,excluded.plays)'
            else:
                statement += ' ON CONFLICT(id) DO NOTHING'
            output.write(statement + ';\n')
connection.close()
print(f'Exported application data to {target}')
