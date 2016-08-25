#!/usr/bin/env python

import sys
import os
import MySQLdb
import time

db = sys.argv[1]

if len(sys.argv) < 3:
	#print('No .upload files in incoming, so nothing to do\n')
	exit(0)

conf = open(os.path.expanduser('~/.repo-script.sh'), 'r')
cf = {}
for i in conf.readlines():
	p = i.strip().split('=')
	cf[p[0]]=p[1]

conn = MySQLdb.connect(host=cf['MYSQL_HOST'],user=cf['MYSQL_USER'],passwd=cf["MYSQL_PASSWORD"],db=db,charset="utf8")
cursor = conn.cursor()

for i in sys.argv[2:]:
	tmp=open(i)
	l=tmp.readline().strip().split(' ')
	tmp.close()
	if len(l)<4:
		print('file %s broken, skipped\n' % (i,))
	pkg=l[0]
	ver=l[1]
	arch=l[2]
	status=l[3]
	table=arch
	sql1 = 'UPDATE '+table+' SET '
	sql1 += " status='" + status +"'"
	if len(l)>4:
		date=l[4]
		sql1 += ", date='" + date +"'"
	if len(l)>5:
		fstage=l[5]
		sql1 += ", fstage='" + fstage +"'"
	if len(l)>6:
		summary=l[6]
		sql1 += ", summary='" + summary +"'"
	if len(l)>7:
		buildd=l[7]
		sql1 += ", buildd='" + buildd +"'"
	if len(l)>8:
		time=l[8]
		sql1 += ", time='" + time +"'"
	if len(l)>9:
		disk=l[9]
		sql1 += ", disk='" + disk +"'"
	sql2 = " where pkg='%s' and ver='%s'" % (pkg, ver)
	sql=sql1+sql2
	cursor.execute(sql)
	conn.commit()
	os.unlink(i)

conn.close()
