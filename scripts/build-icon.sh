#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
source_icon="${project_root}/Assets/AppIcon.png"
output_icon="${1:-${project_root}/.build/AppIcon.icns}"
iconset="${project_root}/.build/iconset/AppIcon.iconset"

if [[ ! -f "${source_icon}" ]]; then
    echo "아이콘 원본을 찾을 수 없습니다: ${source_icon}" >&2
    exit 1
fi

mkdir -p "${iconset}" "${output_icon:h}"
for size in 16 32 128 256 512; do
    sips -s format png -z "${size}" "${size}" "${source_icon}" \
        --out "${iconset}/icon_${size}x${size}.png" >/dev/null
    retina_size=$((size * 2))
    sips -s format png -z "${retina_size}" "${retina_size}" "${source_icon}" \
        --out "${iconset}/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "${iconset}" -o "${output_icon}"
