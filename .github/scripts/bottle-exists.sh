#!/usr/bin/env bash
# Decide whether the GHCR bottle for a given formula + version + platform tag
# already exists, so CI can skip an expensive source rebuild.
#
# Homebrew keys a bottle by version + rebuild + platform tag, never by the
# source archive SHA. A published bottle lives in an OCI image index at
#   <registry>/<image>/manifests/<version-rebuild>
# and each per-platform child manifest carries the annotation
#   org.opencontainers.image.ref.name = "<version-rebuild>.<bottle_tag>"
# (verified against homebrew/core, e.g. "1.25.0_2.arm64_tahoe"). We check for
# the child matching THIS runner's bottle_tag, not just the index tag, because
# the index can hold one platform while another is still missing.
#
# Usage: bottle-exists.sh <registry_base> <image> <index_tag> <ref_name> <bearer>
#   registry_base  e.g. https://ghcr.io/v2/kylerjensen/tap
#   image          GHCR image name (formula name, @->/ and +->x)
#   index_tag      version with -<rebuild> appended only when rebuild > 0
#   ref_name       "<index_tag>.<bottle_tag>" to match a child manifest
#   bearer         GHCR pull token (base64 of a packages:read GITHUB_TOKEN)
#
# Exit 0  = bottle for this platform already published (skip the build).
# Exit 1  = absent (build it).
# Exit 2  = indeterminate (registry error / unexpected status); caller should
#           treat as "build to be safe".
set -euo pipefail

registry_base="$1"
image="$2"
index_tag="$3"
ref_name="$4"
bearer="$5"

url="${registry_base}/${image}/manifests/${index_tag}"
accept='application/vnd.oci.image.index.v1+json'

body="$(mktemp)"
trap 'rm -f "${body}"' EXIT

code="$(curl -sS -o "${body}" -w '%{http_code}' \
  -H "Authorization: Bearer ${bearer}" \
  -H "Accept: ${accept}" \
  "${url}")"

case "${code}" in
  404)
    echo "No index for ${image}:${index_tag}; bottle absent." >&2
    exit 1
    ;;
  200)
    # Index present; require a child manifest for this platform's ref.name.
    # Parse with `brew ruby` (always available in CI) rather than python3/jq,
    # which the ghcr.io/homebrew/brew container does not ship.
    if brew ruby -e '
      require "json"
      index = JSON.parse(File.read(ARGV[0]))
      want = ARGV[1]
      found = index.fetch("manifests", []).any? do |m|
        m.fetch("annotations", {})["org.opencontainers.image.ref.name"] == want
      end
      exit(found ? 0 : 1)
    ' "${body}" "${ref_name}"
    then
      echo "Bottle ${ref_name} already published; skipping build." >&2
      exit 0
    else
      echo "Index exists but no child for ${ref_name}; bottle absent for this platform." >&2
      exit 1
    fi
    ;;
  *)
    echo "Unexpected GHCR status ${code} for ${url}; building to be safe." >&2
    exit 2
    ;;
esac
