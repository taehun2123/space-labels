#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
app_parent="${1:-${project_root}/dist}"
app_path="${app_parent}/Space Labels.app"
mkdir -p "${project_root}/.build/clang-cache" "${project_root}/.build/swiftpm-cache" "${app_parent}"
export CLANG_MODULE_CACHE_PATH="${project_root}/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="${project_root}/.build/swiftpm-cache"

cd "${project_root}"
swift build -c release --disable-sandbox --scratch-path .build --product SpaceLabels -Xswiftc -gnone
binary_path="$(swift build -c release --disable-sandbox --scratch-path .build --show-bin-path)/SpaceLabels"
mkdir -p "${app_path}/Contents/MacOS" "${app_path}/Contents/Resources"
cp "${binary_path}" "${app_path}/Contents/MacOS/SpaceLabels"
cp "${project_root}/Info.plist" "${app_path}/Contents/Info.plist"
"${project_root}/scripts/build-icon.sh" "${app_path}/Contents/Resources/AppIcon.icns"
chmod 755 "${app_path}/Contents/MacOS/SpaceLabels"
codesign --force --sign - "${app_path}"
codesign --verify --deep --strict "${app_path}"
echo "${app_path}"
