#!/bin/bash

# MYSQL_HOST, $MYSQL_USER, MYSQL_PASSWORD
# MAX_JOBS

LC_ALL=C date -u
TMP_SEC=$(awk 'BEGIN{srand();printf "%.16f\n",rand()}')
sleep $(echo $TMP_SEC*30 | bc)


cd ~/chroot
. ~/chroot/bin/buildd-client.conf
HOSTNAME=`hostname`
ARCH=$1
DIST=$2
if [ "$ARCH" = "amd64" ];then
	MAX_JOBS=6
fi

if [ -z "$(echo $allowed_arch | grep $ARCH)" ];then
	echo "arch $ARCH is not allowed"
	exit 1
fi
if [ -z "$(echo $allowed_dist | grep $DIST)" ];then
	echo "dist $DIST is not allowed"
	exit 1
fi

if [ "$(dpkg-architecture -qDEB_BUILD_ARCH)" != "$ARCH" ];then
	export DEB_BUILD_OPTIONS="$DEB_BUILD_OPTIONS nocheck"
	PBUILDERRC=pbuilderrc
fi

if [ "$REMOVE_OLDFILES" = "yes" ];then
	for i in `ls -d sbuild/*/* 2>/dev/null`;do
		pp=$(echo $i | awk -F'/' '{print $NF}')
		tmp=`cat ~/chroot/stamps/* |sed 's/ /_/' | grep $pp`
		if [ -z "$tmp" ];then
			rm -rf $i &
		fi
	done
fi
rmdir sbuild/* 2>/dev/null

for i in `ls .my.cnf.* .pgpass.* 2>/dev/null`;do
	uu=`echo $i | awk -F. '{print $NF}'`
	[ -z "$(ls stamps | grep $uu)" ] && rm -f $i
done

PROJECT=$(eval echo \$$DIST)
PROJECT_HOME=$(eval echo \$$PROJECT)
DB=${PROJECT}${DIST}
UUID=`uuidgen`

[ "$(ls stamps 2>/dev/null | wc -l)" -ge "${MAX_JOBS}" ] && exit 0
touch ~/chroot/stamps/$UUID
trap "rm -f ~/chroot/stamps/$UUID ~/chroot/.my.cnf.$UUID ~/chroot/.pgpass.$UUID" EXIT

if [ "$DB_TYPE" = "MYSQL" ];then
	rm -f .my.cnf.$UUID
	touch .my.cnf.$UUID
	chmod 600 .my.cnf.$UUID
	echo "[client]" >> .my.cnf.$UUID
	echo "password=$MYSQL_PASSWORD" >> .my.cnf.$UUID
elif [ "$DB_TYPE" = "POSTGRE" ];then
	rm -f .pgpass.$UUID
	touch .pgpass.$UUID
	chmod 600 .pgpass.$UUID
	echo "${POSTGRE_HOST}:5432:${DB}:${POSTGRE_USER}:${POSTGRE_PASSWORD}" > .pgpass.$UUID
	export PGPASSFILE=$(pwd)/.pgpass.$UUID 
else
	echo "Error: unknow DB_TYPE: only MYSQL and POSTGRE are supported"
	exit -1
fi


get_buildable_tmp_postgre(){
PGPASSFILE=.pgpass.$UUID psql --no-password -h$POSTGRE_HOST $DB $POSTGRE_USER <<EOF
SELECT pkg,ver FROM $ARCH WHERE status='waiting' LIMIT 1;
EOF
}
get_buildable_tmp(){
if [ "$DB_TYPE" = "MYSQL" ];then
mysql --defaults-file=.my.cnf.$UUID -h$MYSQL_HOST -u$MYSQL_USER $DB <<EOF
SELECT pkg,ver FROM $ARCH WHERE status='waiting' LIMIT 1;
EOF
elif [ "$DB_TYPE" = "POSTGRE" ];then
	get_buildable_tmp_postgre | tail -n +3 | head -n -2 | sed 's/|//g' | xargs
fi
}

mark_status(){
local pkg=$1
local ver=$2
local date=$3
local status=$4
local disk=$5
local time=$6
local fstage=$7
local summary=$8
local buildd=$HOSTNAME
local cmd=""
if [ "$DB_TYPE" = "MYSQL" ];then
	cmd="mysql --defaults-file=.my.cnf.$UUID -h$MYSQL_HOST -u$MYSQL_USER $DB"
elif [ "$DB_TYPE" = "POSTGRE" ];then
	cmd="psql --no-password -h$POSTGRE_HOST $DB $POSTGRE_USER"
else
	return
fi

$cmd <<EOF
UPDATE $ARCH SET status='$status', date='$date', buildd='$buildd', disk='$disk', time='$time', fstage='$fstage', summary='$summary' WHERE pkg='$pkg' and ver='$ver';
EOF
}

ssh ${ARCHIVE_USER}@${ARCHIVE_HOST} "mkdir ~/${PROJECT_HOME}/incoming-$DIST/${ARCH}-stamp" 2>&1
[ "$?" -ne "0" ] && exit 0

PKG_V=$(get_buildable_tmp |grep -v -e "^pkg.*ver$")
echo $PKG_V | tee ~/chroot/stamps/$UUID
if [ -z "$(echo $PKG_V |grep '.* .*')" ];then
	ssh ${ARCHIVE_USER}@${ARCHIVE_HOST} "rmdir ~/${PROJECT_HOME}/incoming-$DIST/${ARCH}-stamp" 2>&1
	exit 0
fi
pkg=$(echo $PKG_V | cut -d' ' -f1)
ver=$(echo $PKG_V | cut -d' ' -f2)
date=$(LC_ALL=C date +%s)
mark_status $pkg $ver $date "building"
ssh ${ARCHIVE_USER}@${ARCHIVE_HOST} "rmdir ~/${PROJECT_HOME}/incoming-$DIST/${ARCH}-stamp" >/dev/null 2>&1
[ "$?" -ne "0" ] && exit 0

########

pkg_v=${pkg}_${ver}
if [ "$(echo $pkg |cut -c1-3)" = "lib" ];then
	subdir="$(echo $pkg |cut -c1-4)"
else
	subdir="$(echo $pkg |cut -c1)"
fi

# FIXME: get correct status, disk,
status="failed"
disk="null"
time="null"
rm -rf sbuild/$subdir/$pkg_v; mkdir -p sbuild/$subdir/$pkg_v; cd sbuild/$subdir/$pkg_v
pkg_cv=$(echo $pkg_v | sed 's/_[1-9]*:/_/g')

if [ "$BUILDD_TOOL" = 'pbuilder' ];then
	apt-get source -oAPT::Get::Only-Source=yes --download-only ${pkg}=${ver}
	if [ ! -e ${pkg_cv}.dsc ];then
		rm -f *.dsc
		mark_status $pkg $ver $date $status
		exit 0
	fi
fi

date1=$(LC_ALL=C date +%s)
logfile="${pkg_v}_${ARCH}-${date1}.build"
if [ "$BUILDD_TOOL" = 'pbuilder' ];then
   sudo DEB_BUILD_OPTIONS="$DEB_BUILD_OPTIONS" pbuilder --build \
	  --binary-arch \
          --logfile $logfile --buildresult $(pwd) --configfile ~/chroot/bin/${PBUILDERRC} \
          --basetgz ~/chroot/${DIST}-${ARCH}.tar.gz --buildplace /tmp \
          --timeout 40h \
            ${pkg_cv}.dsc >/dev/null
elif [ "$BUILDD_TOOL" = 'sbuild' ];then
   DEB_BUILD_OPTIONS="$DEB_BUILD_OPTIONS" sbuild -d $DIST --arch=${ARCH} ${pkg_cv}
   find -type l | xargs rm -f
   mv -f *.build $logfile
else
	false
fi

if [ "$?" -eq "0" ];then
	status="successful"
fi
date2=$(LC_ALL=C date +%s)

if [ "$status" = "successful" ];then
	dput -c ~/chroot/bin/dput.cf -u $DB *_$ARCH.changes 2>&1
fi
######## get summary
time=$(echo "${date2}-${date}" | bc)
disk=$(grep '^Build-Space: ' $logfile | cut -d' ' -f2 | tail -1)

[ -z "$time" ] && disk='null'
[ -z "$disk" ] && disk='null'
fstage='null'
summary='null'
if [ "$status" != "successful" ]; then
	if [ -n "$(grep -i "debian/rules.* gave error exit status" $logfile)" ]; then
		status="attempted"
	fi
	if [ -n "$(grep -i "error while loading shared libraries" $logfile)" ]; then
		summary="err-ld-libs"
	elif [ -n "$(grep -i "undefined reference" $logfile)" ]; then
		summary="undef-ref"
	elif [ -n "$(grep -i "operation not supported" $logfile)" ]; then
		summary="op-n-support"
	elif [ -n "$(grep -i "directory not empty" $logfile)" ]; then
		summary="dir-n-empty"
	elif [ -n "$(grep -i "no such file or directory" $logfile)" ]; then
			summary="n-file-dir"
	fi
fi
if [ -n "$(ls ${pkg}*${DB}.upload)" ]; then
	status="uploaded"
fi
#######
mark_status $pkg $ver $date $status $disk $time $fstage $summary
scp ./$logfile ${ARCHIVE_USER}@${ARCHIVE_HOST}:~/${PROJECT_HOME}/incoming-$DIST 2>&1
