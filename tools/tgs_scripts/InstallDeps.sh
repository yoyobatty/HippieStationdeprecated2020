#!/bin/bash
# What a Linux TGS box needs for this game and these scripts: BYOND's 32-bit runtime libraries (rust_g and our own
# libraries are 32-bit too), curl to fetch librust_g.so, and python3 for HippieUpdate.sh. Run by PreCompile.sh and
# WatchdogLaunch.sh. It tries sudo, which fails without passwordless sudo: then install them yourself with the command below.
set -u

missing=0
command -v curl > /dev/null || missing=1
command -v python3 > /dev/null || missing=1
[ -e /usr/lib/i386-linux-gnu/libssl.so.3 ] || missing=1
[ -e /usr/lib32/libstdc++.so.6 ] || missing=1
[ -e /usr/lib32/libz.so.1 ] || missing=1
if [ "$missing" = 0 ]; then
	exit 0
fi

PACKAGES="curl python3 lib32z1 lib32stdc++6 libssl3:i386"
echo "Missing dependencies. If installing them here fails, run this as an administrator:"
echo "  sudo dpkg --add-architecture i386 && sudo apt-get update && sudo apt-get install -y $PACKAGES"
set -e
if [ "$(id -u)" = 0 ]; then
	dpkg --add-architecture i386
	apt-get update
	apt-get install -y $PACKAGES
else
	sudo -n dpkg --add-architecture i386
	sudo -n apt-get update
	sudo -n apt-get install -y $PACKAGES
fi
