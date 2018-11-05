#!/bin/bash
set -e

INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
HOSTNAME="demo-web-app-${INSTANCE_ID}"

# Hostname
echo -n "${HOSTNAME}" > /etc/hostname
hostname -F /etc/hostname
