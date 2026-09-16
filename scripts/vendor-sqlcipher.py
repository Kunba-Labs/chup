#!/usr/bin/env python3
"""Regenerate the vendored SQLCipher amalgamation from reviewed official source."""
import pathlib, subprocess, shutil
root=pathlib.Path(__file__).resolve().parents[1]
source=root/'.artifacts/sqlcipher-source'
revision='c4b275a47932888216bade83aff2bbc73df0ff85'  # official v4.19.0
if not source.exists():
    subprocess.run(['git','clone','--no-checkout','https://github.com/sqlcipher/sqlcipher.git',str(source)],check=True)
subprocess.run(['git','-C',str(source),'checkout','--detach',revision],check=True)
subprocess.run(['./configure','--with-tempstore=yes','--disable-shared',
 'CFLAGS=-DSQLITE_HAS_CODEC -DSQLCIPHER_CRYPTO_CC -DSQLITE_ENABLE_FTS5 -DSQLITE_EXTRA_INIT=sqlcipher_extra_init -DSQLITE_EXTRA_SHUTDOWN=sqlcipher_extra_shutdown',
 'LDFLAGS=-framework Security'],cwd=source,check=True)
subprocess.run(['make','sqlite3.c'],cwd=source,check=True)
shutil.copy2(source/'sqlite3.c',root/'Sources/CSQLite/sqlcipher.inc')
shutil.copy2(source/'sqlite3.h',root/'Sources/CSQLite/include/sqlite3.h')
shutil.copy2(source/'LICENSE.md',root/'App/Resources/Licenses/SQLCipher.txt')
shutil.copy2(source/'SQLITE_LICENSE.md',root/'App/Resources/Licenses/SQLite.txt')
