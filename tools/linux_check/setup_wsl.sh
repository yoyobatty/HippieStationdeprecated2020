#!/bin/bash
# Sets up a Linux box (a WSL distro, as root) to run the game headless: BYOND's Linux server in /byond and the 32-bit libraries it and
# our native engines need (the same packages as tools/tgs_scripts/InstallDeps.sh and the Dockerfile).
# On Windows: wsl --import HippieLinux <folder> ubuntu-noble-wsl-amd64-wsl.rootfs.tar.gz (cloud-images.ubuntu.com/wsl/releases/24.04/current/),
# then: wsl -d HippieLinux -u root -- bash tools/linux_check/setup_wsl.sh   (from the repository, through /mnt/c)
# BYOND=516.1688 by default.
set -eu
export DEBIAN_FRONTEND=noninteractive
dpkg --add-architecture i386
apt-get update -q
apt-get install -y -q --no-install-recommends ca-certificates curl unzip make lib32z1 lib32stdc++6 libssl3:i386 libcurl4:i386 python3
V="${BYOND:-516.1688}"
if [ ! -x /byond/bin/DreamDaemon ] || ! /byond/bin/DreamDaemon -version 2>&1 | grep -q "${V#*.}"; then
	rm -rf /byond
	curl -fsSL "https://www.byond.com/download/build/${V%%.*}/${V}_byond_linux.zip" -o /tmp/byond.zip
	unzip -q -o /tmp/byond.zip -d /
	(cd /byond && make here) # its Makefile goes by $PWD, which make -C leaves as wherever this was run from
	rm -f /tmp/byond.zip
fi
echo "BYOND: $(LD_LIBRARY_PATH=/byond/bin /byond/bin/DreamDaemon -version 2>&1 | head -1)"
