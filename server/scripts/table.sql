create table (pkg text, ver text, date text, status text, fstage text, summary text, buildd text, time text, disk text);
# pkg: package name
# ver: version
# date: last status changing timestamp
# status: waiting/building, see buildable.sh
# fstage:
# summary:
# buildd: on which build node, hostname
# time: the time cost to build this package
# disk: disk useage to build this package
