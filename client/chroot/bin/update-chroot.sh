#!/bin/sh

sudo apt-get update

. ~/chroot/bin/buildd-client.conf

ARCH=$1
DIST=$2
if [ -z "$(echo $allowed_arch | grep $ARCH)" ];then
	echo "arch $ARCH is not allowed"
	exit 1
fi
if [ -z "$(echo $allowed_dist | grep $DIST)" ];then
	echo "dist $DIST is not allowed"
	exit 1
fi

sudo pbuilder  \
    --execute --save-after-exec \
    --basetgz ~/chroot/${DIST}-${ARCH}.tar.gz \
    --configfile ~/chroot/bin/pbuilderrc \
    --buildplace /tmp \
       ~/chroot/bin/update-chroot-inner.sh

u=$(whoami)

sudo chown ${u}:${u} ~/chroot/${DIST}-${ARCH}.tar.gz 
