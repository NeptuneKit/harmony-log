#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <version>" >&2
  exit 1
fi

version_name="$1"
tmp_proj="${RUNNER_TEMP:-/tmp}/harmony-log-ohpm-publish"
rm -rf "${tmp_proj}"
mkdir -p "${tmp_proj}/hvigor" "${tmp_proj}/library/src/main/ets" "${tmp_proj}/library/src/main" "${tmp_proj}/AppScope"

cat > "${tmp_proj}/oh-package.json5" <<'JSON'
{
  "modelVersion": "5.0.0",
  "description": "Project shell for building harmony-log HAR module.",
  "dependencies": {},
  "devDependencies": {}
}
JSON

cat > "${tmp_proj}/hvigor/hvigor-config.json5" <<'JSON'
{
  "modelVersion": "5.0.0",
  "dependencies": {},
  "execution": {},
  "logging": {},
  "debugging": {},
  "nodeOptions": {}
}
JSON

cat > "${tmp_proj}/hvigorfile.ts" <<'TS'
import { appTasks } from '@ohos/hvigor-ohos-plugin'

export default {
  system: appTasks,
  plugins: []
}
TS

cat > "${tmp_proj}/build-profile.json5" <<'JSON'
{
  "app": {
    "products": [
      {
        "name": "default",
        "compatibleSdkVersion": "5.0.0(12)",
        "targetSdkVersion": "5.0.0(12)",
        "runtimeOS": "HarmonyOS",
        "buildOption": {
          "strictMode": {
            "useNormalizedOHMUrl": true
          }
        }
      }
    ],
    "buildModeSet": [
      {
        "name": "release"
      }
    ]
  },
  "modules": [
    {
      "name": "harmony_log",
      "srcPath": "./library"
    }
  ]
}
JSON

cat > "${tmp_proj}/AppScope/app.json5" <<JSON
{
  "app": {
    "bundleName": "io.github.neptunekit.harmony.log",
    "vendor": "NeptuneKit",
    "versionCode": 1,
    "versionName": "${version_name}"
  }
}
JSON

cat > "${tmp_proj}/library/hvigorfile.ts" <<'TS'
import { harTasks } from '@ohos/hvigor-ohos-plugin'

export default {
  system: harTasks,
  plugins: []
}
TS

cat > "${tmp_proj}/library/build-profile.json5" <<'JSON'
{
  "apiType": "stageMode",
  "targets": [
    {
      "name": "default"
    }
  ]
}
JSON

cat > "${tmp_proj}/library/oh-package.json5" <<JSON
{
  "name": "neptunekit-harmony-log",
  "version": "${version_name}",
  "description": "Swift-log style logger for HarmonyOS.",
  "main": "Index.ets",
  "author": "NeptuneKit",
  "license": "MIT",
  "compatibleSdkVersion": 12,
  "dependencies": {},
  "devDependencies": {},
  "dynamicDependencies": {}
}
JSON

cat > "${tmp_proj}/library/Index.ets" <<'TS'
export * from './src/main/ets/HarmonyLog'
TS

cp src/main/ets/HarmonyLog.ets "${tmp_proj}/library/src/main/ets/HarmonyLog.ets"
cp src/main/ets/HarmonyLogCore.ets "${tmp_proj}/library/src/main/ets/HarmonyLogCore.ets"
cp src/main/module.json5 "${tmp_proj}/library/src/main/module.json5"

cat > "${tmp_proj}/.ohpmrc" <<'CFG'
registry=https://ohpm.openharmony.cn/ohpm/
publish_registry=https://ohpm.openharmony.cn/ohpm/
strict_ssl=true
CFG

cd "${tmp_proj}"
ohpm install

discovered_bin=""
discovered_node_script=""
fixed_candidates=(
  "${HOME}/harmonyOS-command-line-tools/bin/hvigorw"
  "${HOME}/harmonyOS-command-line-tools/bin/hvigor"
  "${HOME}/harmonyOS-command-line-tools/hvigor/bin/hvigorw"
  "${HOME}/harmonyOS-command-line-tools/hvigor/bin/hvigor"
  "${HOME}/harmonyOS-command-line-tools/hvigor/hvigor/bin/hvigor.js"
  "${HOME}/harmonyOS-command-line-tools/node_modules/.bin/hvigorw"
  "${HOME}/harmonyOS-command-line-tools/node_modules/.bin/hvigor"
)

for candidate in "${fixed_candidates[@]}"; do
  if [[ "${candidate}" == *"/hvigor.js" && -f "${candidate}" ]]; then
    discovered_node_script="${candidate}"
  fi
  if [[ -x "${candidate}" ]]; then
    discovered_bin="${candidate}"
    break
  fi
done

if [[ -z "${discovered_bin}" ]]; then
  while IFS= read -r candidate; do
    if [[ "${candidate}" == *"/hvigor.js" && -f "${candidate}" ]]; then
      discovered_node_script="${candidate}"
    fi
    if [[ -z "${discovered_bin}" && -f "${candidate}" && -x "${candidate}" ]]; then
      discovered_bin="${candidate}"
    fi
  done < <(find "${HOME}" "${tmp_proj}" -maxdepth 14 -type f \( -name "hvigor" -o -name "hvigorw" -o -name "hvigor.js" \) 2>/dev/null | sort -u)
fi

if [[ -n "${HVIGOR_BIN:-}" && -x "${HVIGOR_BIN}" ]]; then
  "${HVIGOR_BIN}" --mode module -p module=harmony_log assembleHar --no-daemon
elif [[ -n "${HVIGORW_BIN:-}" && -x "${HVIGORW_BIN}" ]]; then
  "${HVIGORW_BIN}" --mode module -p module=harmony_log assembleHar --no-daemon
elif command -v hvigorw >/dev/null 2>&1; then
  "$(command -v hvigorw)" --mode module -p module=harmony_log assembleHar --no-daemon
elif command -v hvigor >/dev/null 2>&1; then
  "$(command -v hvigor)" --mode module -p module=harmony_log assembleHar --no-daemon
elif [[ -n "${discovered_bin}" ]]; then
  "${discovered_bin}" --mode module -p module=harmony_log assembleHar --no-daemon
elif [[ -n "${discovered_node_script}" ]]; then
  node "${discovered_node_script}" --mode module -p module=harmony_log assembleHar --no-daemon
else
  echo "Cannot find hvigor executable for build." >&2
  find "${HOME}" "${tmp_proj}" -maxdepth 10 \( -name "hvigor" -o -name "hvigorw" -o -name "hvigor.js" \) -print >&2 2>/dev/null || true
  exit 1
fi

har_path="$(find "${tmp_proj}/library/build" -type f -name '*.har' | head -n 1)"
if [[ -z "${har_path}" || ! -f "${har_path}" ]]; then
  echo "No .har artifact found." >&2
  exit 1
fi

if [[ -n "${GITHUB_ENV:-}" ]]; then
  echo "HAR_FILE_PATH=${har_path}" >> "${GITHUB_ENV}"
fi

echo "${har_path}"
