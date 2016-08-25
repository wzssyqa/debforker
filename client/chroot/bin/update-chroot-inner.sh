#!/bin/sh

apt-get update
apt-get dist-upgrade --allow-downgrades -y
apt-get clean
