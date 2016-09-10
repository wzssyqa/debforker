#!/usr/bin/env python

import sys
import os
import time
import apt_pkg
apt_pkg.init_system()


def in_current_table(pkg, ver, c_t):
	for i in c_t:
		if (pkg == i[0]) and (apt_pkg.version_compare(i[1], ver) >= 0):
			return True
	return False

def in_current_list(pkg, ver, c_l):
	for i in c_l:
		if (pkg == i[0]) and (apt_pkg.version_compare(i[1], ver) > 0):
			return True
	return False

def in_blacklist(pkg, blacklist):
	if pkg in blacklist:
		return True
	return False
	#for b in blacklist:
	#	if pkg.startswith(b):
	#		return True
	#return False

db = sys.argv[1]
table = sys.argv[2]

conf = open(os.path.expanduser('~/.repo-script.sh'), 'r')
cf = {}
for i in conf.readlines():
	p = i.strip().split('=')
	if len(p) < 2:
		continue
	cf[p[0]]=p[1]

# some package may make build machine down
if 'BLACKLIST_PACKAGES' in cf:
	p_blacklist = cf['BLACKLIST_PACKAGES'].strip().split(" ")
else:
	p_blacklist = ['gcc-4.9', 'gcc-4.7', 'gcc-5', 'globus-']

if cf['DB_TYPE'] == 'MYSQL':
	import MySQLdb
	conn = MySQLdb.connect(host=cf['MYSQL_HOST'], user=cf['MYSQL_USER'], passwd=cf["MYSQL_PASSWORD"], db=db, charset="utf8")
elif cf['DB_TYPE'] == 'POSTGRE':
	import psycopg2
	conn = psycopg2.connect(host=cf['POSTGRE_HOST'], user=cf['POSTGRE_USER'], password=cf["POSTGRE_PASSWORD"], database=db)
else:
	sys.exit(1)

cursor = conn.cursor()

sql = "select pkg,ver from %s" % (table)
cursor.execute(sql)

current_table=cursor.fetchall()

i_sql = "insert into %s(pkg, ver, date, status) values " % (table)
insert_sql=[]
delete_list=[]
plist=open("temp/"+table+"-buildable.txt",'r')
p_list=[]
for i in plist:
	t=i.strip().split(' ')
	pkg=t[0]
	ver=t[1]
	p_list.append([pkg, ver])

for i in p_list:
	pkg=i[0]
	ver=i[1]
	
	if in_blacklist(pkg, p_blacklist):
		continue
	if in_current_table(pkg, ver, current_table):
		continue
	if in_current_list(pkg, ver, p_list):
		continue
	
	delete_list.append("(pkg='%s' and ver!='%s')" % (pkg, ver))
        insert_sql.append("('%s', '%s', '%s', 'waiting')" % (pkg, ver, str(int(time.time()))))

if len(insert_sql) > 0:
	i_sql += ", ".join(insert_sql)
	cursor.execute(i_sql)

if len(delete_list) >0:
	d_sql = "delete from %s where status = 'attempted' and (%s)" % (table, " or ".join(delete_list))
	cursor.execute(d_sql)

sql="delete from %s where status='failed'" % (table)
cursor.execute(sql)

conn.commit()

