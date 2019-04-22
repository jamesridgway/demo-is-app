#!/bin/bash
set -e

gem install bundler
gem update --system
sudo chown -R webapp:webapp /srv/demowebapp

(
    cd /srv/demowebapp
    sudo -u webapp bundle install --path /srv/demowebapp/.bundle
)

sudo -u webapp bash <<"EOF"
cd /srv/demowebapp
export RAILS_ENV=test
bundle exec rails db:environment:set
bundle exec rake db:drop db:create db:migrate
bundle exec rspec --format documentation --format RspecJunitFormatter --out rspec.xml
git rev-parse HEAD > REVISION
EOF

sudo mkdir -p /usr/lib/systemd/system
cp /srv/demowebapp/build/system.d/demowebapp.service /usr/lib/systemd/system/demowebapp.service
cp /srv/demowebapp/build/user-data.sh /etc/rc.local
chmod +x /etc/rc.local
systemctl enable demowebapp.service
