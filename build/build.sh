#!/bin/bash
cd "$(dirname "$0")" || exit

rm -f ../REVISION
rm -rf ../coverage/
rm -rf ../log/*.log
rm -rf ../public/system

jq '.builders[0].tags.Commit = "'"$(git rev-parse HEAD)"'"' packer.json > packer-versioned.json
rm -f manifest.json
packer build packer-versioned.json

cat manifest.json
