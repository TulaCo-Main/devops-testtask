#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

region=eu-central-1
registry=056300054271.dkr.ecr.eu-central-1.amazonaws.com

aws ecr get-login-password --region "$region" |
  sudo docker login --username AWS --password-stdin "$registry"
sudo docker compose build nodeapp
sudo docker compose push nodeapp
