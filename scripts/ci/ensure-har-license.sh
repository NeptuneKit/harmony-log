#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <har-path> <license-path>" >&2
  exit 1
fi

har_path="$1"
license_path="$2"

if [[ ! -f "${har_path}" ]]; then
  echo "HAR file not found: ${har_path}" >&2
  exit 1
fi

if [[ ! -f "${license_path}" ]]; then
  echo "License file not found: ${license_path}" >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

tar -xzf "${har_path}" -C "${tmp_dir}"
mkdir -p "${tmp_dir}/package"
cp -f "${license_path}" "${tmp_dir}/package/LICENSE"

(
  cd "${tmp_dir}"
  tar -czf "${har_path}" package
)

echo "Injected LICENSE into ${har_path}"
