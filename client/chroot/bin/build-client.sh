#!/bin/bash

# MYSQL_HOST, $MYSQL_USER, MYSQL_PASSWORD
# MAX_JOBS

LC_ALL=C date -u

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
	PBUILDERRC=pbuilderrc-nocheck
else
	PBUILDERRC=pbuilderrc
fi

PROJECT=$(eval echo \$$DIST)
PROJECT_HOME=$(eval echo \$$PROJECT)
DB=${PROJECT}${DIST}
UUID=`uuidgen`

[ "$(ls stamps 2>/dev/null | wc -l)" -ge "${MAX_JOBS}" ] && exit 0
touch ~/chroot/stamps/$UUID
trap "rm -f ~/chroot/stamps/$UUID" EXIT

get_buildable_tmp(){
mysql -h$MYSQL_HOST -u$MYSQL_USER -p$MYSQL_PASSWORD $DB <<EOF
SELECT pkg,ver FROM $ARCH WHERE status='waiting' LIMIT 1;
EOF
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
mysql -h$MYSQL_HOST -u$MYSQL_USER -p$MYSQL_PASSWORD $DB <<EOF
UPDATE $ARCH SET status="$status", date="$date", buildd="$buildd", disk="$disk", time="$time", fstage="$fstage", summary="$summary" WHERE pkg="$pkg" and ver="$ver";
EOF
}

ssh repo@${MYSQL_HOST} "mkdir ~/${PROJECT_HOME}/incoming/${ARCH}-stamp" 2>&1
[ "$?" -ne "0" ] && exit 0

PKG_V=$(get_buildable_tmp |grep -v -e "^pkg.*ver$")
echo $PKG_V
if [ -z "$(echo $PKG_V |grep '.* .*')" ];then
	ssh repo@${MYSQL_HOST} "rmdir ~/${PROJECT_HOME}/incoming/${ARCH}-stamp" 2>&1
	exit 0
fi
pkg=$(echo $PKG_V | cut -d' ' -f1)
ver=$(echo $PKG_V | cut -d' ' -f2)
date=$(LC_ALL=C date +%s)
mark_status $pkg $ver $date "building"
ssh repo@${MYSQL_HOST} "rmdir ~/${PROJECT_HOME}/incoming/${ARCH}-stamp" >/dev/null 2>&1
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

apt-get source --download-only ${pkg}=${ver}
if [ ! -e ${pkg_cv}.dsc ];then
	rm -f *.dsc
	mark_status $pkg $ver $date $status
	exit 0
fi

date1=$(LC_ALL=C date +%s)
logfile="${pkg_v}_${ARCH}-${date1}.build"
if [ "$ARCH" = "amd64" ];then
   sudo DEB_BUILD_OPTIONS="$DEB_BUILD_OPTIONS" pbuilder --build \
	  --debbuildopts "-b --hook-source=\"grep 'dh \$\@ .*--parallel' debian/rules || sed -i '/dh \$\@/ s/$/ --parallel/' debian/rules\"" \
          --logfile $logfile --buildresult $(pwd) --configfile ~/chroot/bin/${PBUILDERRC} \
          --basetgz ~/chroot/${DIST}-${ARCH}.tar.gz --buildplace /tmp \
          --timeout 40h \
            ${pkg_cv}.dsc >/dev/null
else
   sudo DEB_BUILD_OPTIONS="$DEB_BUILD_OPTIONS" pbuilder --build \
	  --binary-arch \
          --logfile $logfile --buildresult $(pwd) --configfile ~/chroot/bin/${PBUILDERRC} \
          --basetgz ~/chroot/${DIST}-${ARCH}.tar.gz --buildplace /tmp \
          --timeout 40h \
            ${pkg_cv}.dsc >/dev/null
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
scp $logfile repo@192.168.252.150:~/${PROJECT_HOME}/incoming 2>&1
