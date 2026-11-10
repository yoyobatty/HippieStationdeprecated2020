#!/bin/bash
# Builds the Dockerfile and boots the image until the game has initialised (in a WSL distro set up by setup_wsl.sh, as root, from the
# repository through /mnt/c). Installs Docker there first if it isn't. MAP=testbench by default; TIMEOUT=300 seconds for the boot.
#   bash tools/linux_check/docker_check.sh
set -u
MAP="${MAP:-testbench}"
TIMEOUT="${TIMEOUT:-300}"
if ! command -v docker > /dev/null; then
	apt-get update -q && DEBIAN_FRONTEND=noninteractive apt-get install -y -q docker.io > /dev/null
fi
if ! docker info > /dev/null 2>&1; then
	(dockerd > /var/log/dockerd.log 2>&1 &)
	for i in $(seq 1 30); do docker info > /dev/null 2>&1 && break; sleep 1; done
	docker info > /dev/null 2>&1 || { echo "dockerd didn't start:"; tail -5 /var/log/dockerd.log; exit 1; }
fi

START=$(date +%s)
docker build -t hippiestation:check . > /root/docker_build.log 2>&1
STATUS=$?
tail -12 /root/docker_build.log
echo "Built in $(( $(date +%s) - START )) s (exit $STATUS)"
[ "$STATUS" = 0 ] || exit 1
docker image ls hippiestation:check --format "Image: {{.Size}}"

CHECK=/root/dockercheck
rm -rf "$CHECK"
mkdir -p "$CHECK/data"
cp -r config "$CHECK/"
docker rm -f hippiecheck > /dev/null 2>&1
docker run -d --name hippiecheck -v "$CHECK/config:/tgstation/config" -v "$CHECK/data:/tgstation/data" hippiestation:check -params "bot-map=$MAP" > /dev/null
BOOT=$(date +%s)
READY=""
while [ $(( $(date +%s) - BOOT )) -lt "$TIMEOUT" ]; do
	sleep 2
	READY="$(grep -rl "Initializations complete" "$CHECK/data/logs" 2>/dev/null | head -n 1)"
	[ -n "$READY" ] && break
	docker ps -q -f name=hippiecheck | grep -q . || break
done
if [ -n "$READY" ]; then
	echo "Booted in $(( $(date +%s) - BOOT )) s"
	grep -hE "Path engine|Atmos:|Lighting: engine|Initializations complete|Shaped explosions" "$CHECK"/data/logs/*/*/*/*/world.log "$READY" 2>/dev/null | sed 's/^\[[^]]*\] //' | sort -u
else
	echo "DIDN'T BOOT within $TIMEOUT s"
	docker logs hippiecheck 2>&1 | tail -20
fi
docker rm -f hippiecheck > /dev/null 2>&1
[ -n "$READY" ]
