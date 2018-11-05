#!/bin/bash
cd "$(dirname "$0")/.." || exit
./bin/bundle exec rails assets:precompile
./bin/bundle exec rake db:migrate
./bin/bundle exec puma -C config/puma.rb