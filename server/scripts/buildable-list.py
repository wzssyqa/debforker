#!/usr/bin/env python

import sys
import os
import time

infile=open(sys.argv[1], 'r')
outfile=open(sys.argv[2], 'a')

while True:
	line=infile.readline()
	if not line:
		break
	if not line.startswith('  package: '):
		continue
	pkg=line.strip().replace('package: ', '').replace("src:", "")
	line=infile.readline()
	if not line.startswith('  version: '):
		continue
	ver=line.strip().replace('version: ', '').strip()

	line=infile.readline()
	if not line.startswith('  architecture: '):
		continue
	arch=line.strip().replace('architecture: ', '').strip()
	if arch == 'all':
		continue

	outfile.write("%s %s\n" % (pkg, ver))

infile.close()
outfile.close()
