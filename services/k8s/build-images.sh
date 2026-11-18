#!/usr/bin/env bash
# Builds the three service images on the VM and loads them into k3s's container runtime.
# Run from the repository root after every code change, then restart the deployments:
#
#   services/k8s/build-images.sh
#   kubectl -n loan-origination rollout restart deployment credit-scoring event-bridge notification-service
set -euo pipefail
cd "$(dirname "$0")/.."

for service in credit-scoring event-bridge notification-service; do
  image="loan-origination/${service}:local"
  echo "Building ${image}"
  docker build -t "${image}" "${service}"
  docker save "${image}" | sudo k3s ctr images import -
done
