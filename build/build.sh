#!/bin/bash
cd "$(dirname "$0")" || exit

rm -f ../REVISION
rm -rf ../coverage/
rm -rf ../log/*.log
rm -rf ../public/system

rm -f manifest.json
packer build -var "commit=$(git rev-parse HEAD)" packer.json

cat manifest.json
