#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
version="${1:-}"
output_directory="${2:-${project_root}/dist}"

if [[ ! "${version}" =~ '^[0-9]+\.[0-9]+\.[0-9]+-preview\.[0-9]+$' ]]; then
    echo "사용법: $0 <0.1.0-preview.1 같은 버전> [출력 폴더]" >&2
    exit 1
fi

architecture="$(uname -m)"
if [[ "${architecture}" != "arm64" ]]; then
    echo "이 스크립트는 Apple Silicon Mac에서만 시험판 DMG를 만듭니다." >&2
    exit 1
fi

mkdir -p "${project_root}/.build" "${output_directory}"
staging_root="$(mktemp -d "${project_root}/.build/release.XXXXXX")"
trap 'rm -rf "${staging_root}"' EXIT

"${project_root}/scripts/build-app.sh" "${staging_root}/built"
mkdir -p "${staging_root}/contents"
ditto "${staging_root}/built/Space Labels.app" "${staging_root}/contents/Space Labels.app"
ln -s /Applications "${staging_root}/contents/Applications"

output_path="${output_directory}/Space-Labels-${version}-macos-arm64.dmg"
hdiutil create -fs HFS+ -srcfolder "${staging_root}/contents" \
    -volname "Space Labels Preview" -format UDZO -ov "${output_path}" >/dev/null
echo "${output_path}"
