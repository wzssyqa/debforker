#!/bin/sh -e

. ~/.repo-script.sh
REPO=$1 

if [ ! -d "$(readlink -f ~/$REPO)" ];then
	echo "~/$1 is not a directory!"
	exit -1;
fi

LOGFILE=~/logs/"$(basename $0)".log

cd ~/$REPO

[ temp/stamp -ot temp/buildable.stamp ] && rm -f temp/stamp
if [ -f temp/stamp ];then
	echo -n "$(LC_ALL=C date -u):  " >> $LOGFILE
	cat temp/stamp >> $LOGFILE 2>&1
	exit 1
fi

echo "$0 $@" >> temp/stamp

DIST=$(cat conf/distributions | grep Suite |head -1 | cut -d' ' -f2)
ARCHES=$(cat conf/distributions | grep Architectures |head -1 | sed 's/amd64//g' | cut -d' ' -f2-)
COMPENENTS=$(cat conf/distributions | grep Components |head -1 | cut -d' ' -f2-)
STATUS_LIST="waiting building attampted failed uploaded installed"

if [ -z "$DIST" ] || [ -z "$ARCHES" ] || [ -z "$COMPENENTS" ];then
	rm -f temp/stamp
	echo -n "$(LC_ALL=C date -u):  " >> $LOGFILE
	exit 1
fi

for a in $ARCHES;do
	[ incoming/${a}-stamp -ot temp/buildable.stamp ] && rmdir incoming/${a}-stamp
done

# buildlog
mkdir -p buildlog
# gcc-5_5.2.1-17ubuntu1_mipsel-20150919-0857.build
for i in `ls incoming/*_*_mips*-*.build 2>/dev/null`;do
	pkg=$(echo $i | cut -d/ -f2 | cut -d_ -f1)
	if [ "$(echo $pkg |cut -c1-3)" = "lib" ];then
                subdir="$(echo $pkg |cut -c1-4)"
        else
                subdir="$(echo $pkg |cut -c1)"
        fi
	mkdir -p buildlog/$subdir/$pkg
	mv -f $i buildlog/$subdir/$pkg
done

# process incoming
# gcc-5_5.2.1-17ubuntu1_mipsel.changes
for i in `ls incoming |grep '.*_.*_.*.changes' 2>/dev/null`;do
	pkg=$(echo $i | cut -d_ -f1)
	if [ -n `echo " $BLACKLIST_PACKAGES " | grep " $pkg "` ];then
		continue
	fi
	ver=$(cat incoming/$i 2>> $LOGFILE| grep '^Version:' | head -1 |awk '{print $2}')
	arch=$(echo $i | cut -d_ -f3 | sed 's/.changes//g')
	dbgsym=$(cat incoming/$i |grep -- -dbgsym_ | cut -d' ' -f 4 | grep '.deb$' | cut -d'_' -f1 |sort |uniq)
	for k in $dbgsym;do
		sed -i "s/^Binary: /Binary: $k /g" incoming/$i
	done
	echo "reprepro processincoming $DIST $i ..." >>$LOGFILE 2>&1
	reprepro processincoming $DIST $i >>$LOGFILE 2>&1
	if [ "$?" -eq 0 ];then
		echo "$pkg $ver $arch installed $(date -u +%s) incoming/${pkg}_${ver}_${arch}.upload" >> $LOGFILE 
		echo "$pkg $ver $arch installed $(date -u +%s)" > incoming/${pkg}_${ver}_${arch}.upload
	fi
done

for i in `find incoming -mmin +90 -a \( -name *.changes -o -name *deb \)`;do
	mv -f $i incoming-overflow/ >/dev/null 2>&1 
done

#       update package status: building, uploaded, installed, attempted.
# File name like pkg_ver_arch.upload
# File contect "pkg ver arch STATUS date fstage summary buildd time disk"
python ~/scripts/update-status.py ubuntu${DIST} $(ls incoming/*.upload 2>/dev/null || true)

LC_ALL=C date > temp/buildable.stamp

for arch in $ARCHES;do
	if [ "$REMOVE_PROJECT_OLD" != "yes" ] || [ ! -d ~/${REPO}-old ];then
		continue
	fi
	reprepro -A $arch list ${DIST} | awk '{print $2}' > temp/has_packages
	to_remove=""
	for i in `reprepro -b ~/${REPO}-old -A $arch list $DIST | cut -d' ' -f2`;do
		tmp=`grep "^$i$" temp/has_packages`
		if [ -n "$tmp" ];then
			to_remove="$to_remove $i"
		fi
	done
	if [ -n "$to_remove" ];then
		reprepro -b ~/${REPO}-old -A $arch remove next $to_remove
	fi
done

if [ "$REMOVE_LOGS_OLD" = "yes" ];then
  for d in `find buildlog -type d`;do
	[ -z "$(ls $d/*.build 2>/dev/null)" ] && continue
	for a in $ARCHES;do
		last="$(ls $d/*_${a}-*.build 2>/dev/null | tail -1)"
		for f in `ls $d/*_${a}-*.build 2>/dev/null | grep -v "$last"`;do
			echo $f
			rm -f $f
		done
	done
  done
fi

if [ "$2" = "noupdate" ];then
	rm -f temp/stamp
	exit 0
fi

echo "$0 $@" >> temp/stamp
reprepro update >> $LOGFILE 2>&1
echo "$0 $@" >> temp/stamp

for a in $ARCHES;do
	BIN_INDEXES=""
	for c in $COMPENENTS;do
		if [ -f ~/${REPO}-old/dists/$DIST/${c}/binary-${a}/Packages.gz ];then
			cp ~/${REPO}-old/dists/$DIST/${c}/binary-${a}/Packages.gz temp/binary_${a}_${c}.gz
		else
			echo | gzip -9 > temp/binary_${a}_${c}.gz
		fi
		BIN_INDEXES="$BIN_INDEXES dists/${DIST}/${c}/binary-${a}/Packages.gz dists/${DIST}-updates/${c}/binary-${a}/Packages.gz temp/binary_${a}_${c}.gz"
	done

	for c in $COMPENENTS;do
		wget -q $MIRROR/$REPO/dists/${DIST}/${c}/source/Sources.gz -O temp/sources_${c}.tmp.gz
		wget -q $MIRROR/$REPO/dists/${DIST}-updates/${c}/source/Sources.gz -O temp/sources_${c}-updates.tmp.gz
		zcat temp/sources_${c}.tmp.gz temp/sources_${c}-updates.tmp.gz 2>/dev/null | grep -v '^Build-Depends-Indep: ' | gzip > temp/sources_${c}.gz
	done
	: > temp/${a}-buildable.txt
	# FIXME: only build main now to save some time.
	for c in $COMPENENTS;do
		dose-builddebcheck --deb-native-arch=$a --successes $BIN_INDEXES temp/sources_${c}.gz > temp/${a}_${c}-buildable.txt 2>>$LOGFILE
		dose-builddebcheck --deb-native-arch=$a --explain --failures $BIN_INDEXES temp/sources_${c}.gz > temp/${a}_${c}-failure.txt 2>>$LOGFILE
		python ~/scripts/buildable-list.py temp/${a}_${c}-buildable.txt temp/${a}-buildable.txt
	done
	python ~/scripts/addto-db.py ubuntu${DIST} $a
done

rm -f temp/stamp
