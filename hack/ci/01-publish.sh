#!/usr/bin/env bash

# Copyright 2023 Chainguard, Inc.
# SPDX-License-Identifier: Apache-2.0

set -ex

REGISTRY_BASE_IMAGE="index.docker.io/library/registry:2.8.1"
REGISTRY_CONTAINER_NAME="ci-testing-registry"
PORT=${PORT:-${RANDOM}}

trap "rm -f *.sbom.json && \
docker rm -f ${REGISTRY_CONTAINER_NAME}" EXIT

docker rm -f "${REGISTRY_CONTAINER_NAME}"
docker run --name "${REGISTRY_CONTAINER_NAME}" \
  -d -p ${PORT}:5000 "${REGISTRY_BASE_IMAGE}"

for f in examples/alpine-base-rootless.yaml examples/wolfi-base.yaml; do
  echo "=== building $f"

  REF="localhost:${PORT}/ci-testing:$(basename ${f})"
  img=$("${APKO}" publish "${f}" "${REF}")

  # Run the image.
  docker run --rm ${img} echo hello | grep hello

  if [[ ${f} == "examples/wolfi-base.yaml" ]]; then
    # Download SBOM and check that it contains
    # files derived from package SBOMs melange produces in /var/lib/db/sbom
    cosign download sbom --platform=linux/amd64 "${REF}" | tee ci-testing.sbom.json
    HAS_FILES="$(cat ci-testing.sbom.json | jq 'keys | contains(["files"])')"
    if [[ "${HAS_FILES}" != "true" ]]; then
      echo "SBOM does not have files. Exiting."
      exit 1
    fi
  fi

  # Each platform should contain platform-specific etc/apk/arch file.
  crane export --platform linux/amd64 "${REF}" | tar -Ox etc/apk/arch | grep x86_64
  crane export --platform linux/arm64 "${REF}" | tar -Ox etc/apk/arch | grep aarch64
done
