#!/bin/bash
cd "$(dirname "$0")" || exit

bundle install --path ./bundle

AMI_ID=$(jq -r '.builds[0].artifact_id' manifest.json | awk -F ':' '{print $2}')
bundle exec ruby deploy.rb "${AMI_ID}"