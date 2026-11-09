#!/bin/bash
# TGS PostCompile (Linux): $1 is the new deployment folder, $2 the BYOND version it was compiled with.
# Boots the new build headless with the smoke boot shipped in that build, and fails the deploy if it doesn't initialize.
exec bash "$1/tools/tgs_scripts/smoke_boot.sh" "$1" "$2"
