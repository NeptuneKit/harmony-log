#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <har-path> <license-path>" >&2
  exit 1
fi

har_path="$1"
license_path="$2"
repo_root="$(cd "$(dirname "${license_path}")" && pwd)"
readme_src="${repo_root}/README.md"
changelog_src="${repo_root}/CHANGELOG.md"

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
if [[ -f "${readme_src}" ]]; then
  cp -f "${readme_src}" "${tmp_dir}/package/readme.md"
fi
if [[ -f "${changelog_src}" ]]; then
  cp -f "${changelog_src}" "${tmp_dir}/package/changelog.md"
else
  cat > "${tmp_dir}/package/changelog.md" <<'MD'
# Changelog

## 1.0.0

- Initial release.
MD
fi
find "${tmp_dir}/package" -name '._*' -delete

(
  cd "${tmp_dir}"
  tar -czf "${har_path}" package
)

echo "Injected LICENSE/readme/changelog into ${har_path}"
