#!/bin/bash
cd "$(dirname "$0")" || exit

bundle install --path ./bundle
bundle exec ruby deploy.rb