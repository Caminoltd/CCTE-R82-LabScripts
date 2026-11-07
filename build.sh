#!/bin/bash
# Rebuilds dist/ from SMS/ and GW/ (run after any script change)
set -e
cd "$(dirname "$0")"
for p in SMS GW; do
  chmod 755 $p/lab* $p/labmenu
  tar --owner=0 --group=0 --numeric-owner --mtime='2026-11-07 00:00Z' --sort=name -czf dist/$p.tgz -C $p $(cd $p && ls)
done
md5sum SMS/* GW/* > dist/manifest.md5
echo "dist rebuilt"
