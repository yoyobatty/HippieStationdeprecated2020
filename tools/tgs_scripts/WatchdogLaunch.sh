#!/bin/bash
# TGS WatchdogLaunch (Linux): make sure the runtime libraries are still there before the game starts (Docker hosts lose them).
exec "$(dirname "$0")/InstallDeps.sh"
