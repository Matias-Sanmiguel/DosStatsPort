#!/usr/bin/env bash
set -euo pipefail

readonly DOSBOX_VERSION="0.83.0"
readonly DOSBOX_BUILD="7b400"
readonly DOSBOX_ARCHIVE="dosbox-staging-linux-x86_64-v${DOSBOX_VERSION}.tar.xz"
readonly DOSBOX_URL="https://github.com/dosbox-staging/dosbox-staging/releases/download/v${DOSBOX_VERSION}/${DOSBOX_ARCHIVE}"
readonly DOSBOX_SHA256="d3a94f7f1c3e68a47ec88d61145506c7904452adb0c9c5928cb8cfe2331d6c5c"
readonly DOSBOX_SOURCE="dosbox-staging-v${DOSBOX_VERSION}-source.tar.gz"
readonly DOSBOX_SOURCE_URL="https://github.com/dosbox-staging/dosbox-staging/archive/refs/tags/v${DOSBOX_VERSION}.tar.gz"
readonly DOSBOX_SOURCE_SHA256="9b36be5a666784adaeffa560bd0950691f851a76bdb97e7ae3c989561e91caf3"
readonly APPIMAGETOOL_URL="https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"
readonly APPIMAGETOOL_SHA256="a6d71e2b6cd66f8e8d16c37ad164658985e0cf5fcaa950c90a482890cb9d13e0"
readonly APPIMAGE_RUNTIME_URL="https://github.com/AppImage/type2-runtime/releases/download/continuous/runtime-x86_64"
readonly APPIMAGE_RUNTIME_SHA256="1cc49bcf1e2ccd593c379adb17c9f85a36d619088296504de95b1d06215aebbf"

root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
version=$(<"$root/VERSION")
input=""
output_dir="$root/dist"
cache_dir="$root/.cache/downloads"
skip_appimage=0

usage() {
    cat <<EOF
Uso: scripts/build-linux.sh --input RUTA [opciones]

  --input RUTA       DIS.zip o el ZIP exterior que contiene DIS.zip.
  --output DIR       Directorio de salida (default: $output_dir).
  --skip-appimage    Construye solo el bundle portable tar.xz.
  -h, --help         Muestra esta ayuda.
EOF
}

die() {
    printf 'build-linux: %s\n' "$*" >&2
    exit 1
}

while (($#)); do
    case "$1" in
        --input)
            (($# >= 2)) || die "falta el valor de --input"
            input=$2
            shift
            ;;
        --output)
            (($# >= 2)) || die "falta el valor de --output"
            output_dir=$2
            shift
            ;;
        --skip-appimage) skip_appimage=1 ;;
        -h|--help)
            usage
            exit 0
            ;;
        *) die "opcion desconocida: $1" ;;
    esac
    shift
done

[[ -n $input ]] || die "use --input para indicar el ZIP entregado por la facultad"
[[ -f $input ]] || die "no existe el input: $input"
[[ $(uname -m) == x86_64 ]] || die "el build Linux actual requiere un host x86_64"
for command_name in curl file install sha256sum tar unzip xz; do
    command -v "$command_name" >/dev/null 2>&1 || die "falta la herramienta '$command_name'"
done

work_dir="$root/build/linux"
app_dir="$work_dir/DIS-Estadistica.AppDir"
portable_name="DIS-Estadistica-${version}-linux-x86_64"
portable_dir="$work_dir/$portable_name"
payload_work="$work_dir/payload"
dosbox_work="$work_dir/dosbox-upstream"
compliance_dir="$output_dir/compliance"

rm -rf -- "$work_dir"
mkdir -p "$work_dir" "$payload_work" "$dosbox_work" "$cache_dir" "$output_dir" "$compliance_dir"

verify_file() {
    local expected=$1
    local path=$2
    printf '%s  %s\n' "$expected" "$path" | sha256sum --check --status
}

fetch() {
    local url=$1
    local destination=$2
    local expected=$3
    local temporary="$destination.part"

    if [[ -f $destination ]] && verify_file "$expected" "$destination"; then
        return
    fi
    rm -f -- "$destination" "$temporary"
    printf 'Descargando %s\n' "$(basename -- "$destination")"
    curl --fail --location --retry 3 --output "$temporary" "$url"
    verify_file "$expected" "$temporary" || die "checksum invalido para $url"
    mv -- "$temporary" "$destination"
}

validate_zip_entries() {
    local zip_path=$1
    local entries
    entries=$(unzip -Z1 "$zip_path") || die "no se pudo listar $zip_path"
    [[ $entries == $'DIS.EXE\nGRAFDIS.EXE\nINVDIS.EXE' || \
       $entries == $'DIS.EXE\nINVDIS.EXE\nGRAFDIS.EXE' || \
       $entries == $'GRAFDIS.EXE\nDIS.EXE\nINVDIS.EXE' || \
       $entries == $'GRAFDIS.EXE\nINVDIS.EXE\nDIS.EXE' || \
       $entries == $'INVDIS.EXE\nDIS.EXE\nGRAFDIS.EXE' || \
       $entries == $'INVDIS.EXE\nGRAFDIS.EXE\nDIS.EXE' ]] || \
        die "el ZIP de DIS debe contener solamente DIS.EXE, GRAFDIS.EXE e INVDIS.EXE"
}

payload_zip=$input
if unzip -Z1 "$input" | grep -Fxq 'DIS.zip'; then
    payload_zip="$work_dir/DIS.zip"
    unzip -p "$input" DIS.zip > "$payload_zip" || die "no se pudo extraer DIS.zip del paquete exterior"
fi

validate_zip_entries "$payload_zip"
unzip -qq "$payload_zip" DIS.EXE GRAFDIS.EXE INVDIS.EXE -d "$payload_work"
cp -- "$root/metadata/payload.sha256" "$payload_work/payload.sha256"
(cd "$payload_work" && awk '/^[0-9a-f]{64}  / {print}' payload.sha256 | sha256sum --check) || \
    die "los ejecutables no coinciden con la copia validada de DIS"
for executable in DIS.EXE GRAFDIS.EXE INVDIS.EXE; do
    file -b "$payload_work/$executable" | grep -q '^MS-DOS executable' || die "$executable no es un ejecutable MS-DOS"
done

dosbox_archive="$cache_dir/$DOSBOX_ARCHIVE"
dosbox_source="$cache_dir/$DOSBOX_SOURCE"
fetch "$DOSBOX_URL" "$dosbox_archive" "$DOSBOX_SHA256"
fetch "$DOSBOX_SOURCE_URL" "$dosbox_source" "$DOSBOX_SOURCE_SHA256"
tar -xJf "$dosbox_archive" -C "$dosbox_work" --strip-components=1
[[ -x $dosbox_work/dosbox && -d $dosbox_work/resources ]] || die "layout inesperado del release de DOSBox Staging"

mkdir -p \
    "$app_dir/usr/bin" \
    "$app_dir/usr/lib/dosbox-staging" \
    "$app_dir/usr/share/dis-estadistica/payload" \
    "$app_dir/usr/share/applications" \
    "$app_dir/usr/share/metainfo" \
    "$app_dir/usr/share/icons/hicolor/scalable/apps" \
    "$app_dir/usr/share/licenses/dis-estadistica"

cp -a -- "$dosbox_work/." "$app_dir/usr/lib/dosbox-staging/"
install -m 0755 "$root/src/dis-estadistica" "$app_dir/usr/bin/dis-estadistica"
install -m 0755 "$root/src/AppRun" "$app_dir/AppRun"
install -m 0644 "$root/config/dosbox.conf" "$app_dir/usr/share/dis-estadistica/dosbox.conf"
install -m 0644 "$root/VERSION" "$app_dir/usr/share/dis-estadistica/VERSION"
install -m 0600 "$payload_work/DIS.EXE" "$app_dir/usr/share/dis-estadistica/payload/DIS.EXE"
install -m 0600 "$payload_work/GRAFDIS.EXE" "$app_dir/usr/share/dis-estadistica/payload/GRAFDIS.EXE"
install -m 0600 "$payload_work/INVDIS.EXE" "$app_dir/usr/share/dis-estadistica/payload/INVDIS.EXE"
install -m 0644 "$payload_work/payload.sha256" "$app_dir/usr/share/dis-estadistica/payload/payload.sha256"
install -m 0644 "$root/LICENSE" "$app_dir/usr/share/licenses/dis-estadistica/LICENSE-MIT"
install -m 0644 "$dosbox_work/LICENSE" "$app_dir/usr/share/licenses/dis-estadistica/LICENSE-DOSBOX-STAGING"
install -m 0644 "$root/packaging/LICENSE-APPIMAGE-RUNTIME" "$app_dir/usr/share/licenses/dis-estadistica/LICENSE-APPIMAGE-RUNTIME"
cp -a -- "$dosbox_work/doc/licenses" "$app_dir/usr/share/licenses/dis-estadistica/dosbox-third-party"
install -m 0644 "$root/packaging/io.github.cauchothegaucho.DosStatsPort.desktop" "$app_dir/usr/share/applications/io.github.cauchothegaucho.DosStatsPort.desktop"
install -m 0644 "$root/packaging/io.github.cauchothegaucho.DosStatsPort.appdata.xml" "$app_dir/usr/share/metainfo/io.github.cauchothegaucho.DosStatsPort.appdata.xml"
install -m 0644 "$root/packaging/dis-estadistica.svg" "$app_dir/usr/share/icons/hicolor/scalable/apps/dis-estadistica.svg"
install -m 0644 "$root/packaging/io.github.cauchothegaucho.DosStatsPort.desktop" "$app_dir/io.github.cauchothegaucho.DosStatsPort.desktop"
install -m 0644 "$root/packaging/dis-estadistica.svg" "$app_dir/dis-estadistica.svg"

cat > "$app_dir/usr/share/dis-estadistica/BUILD-INFO" <<EOF
DosStatsPort version: $version
DOSBox Staging version: $DOSBOX_VERSION ($DOSBOX_BUILD)
DOSBox binary SHA-256: $DOSBOX_SHA256
DOSBox source SHA-256: $DOSBOX_SOURCE_SHA256
AppImage tool SHA-256: $APPIMAGETOOL_SHA256
AppImage runtime SHA-256: $APPIMAGE_RUNTIME_SHA256
Architecture: x86_64
Build date: $(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

cp -a -- "$app_dir" "$portable_dir"
cat > "$portable_dir/run.sh" <<'EOF'
#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec "$ROOT/usr/bin/dis-estadistica" "$@"
EOF
chmod 0755 "$portable_dir/run.sh"

portable_archive="$output_dir/$portable_name.tar.xz"
rm -f -- "$portable_archive"
tar -cJf "$portable_archive" -C "$work_dir" "$portable_name"

appimage_path="$output_dir/DIS-Estadistica-${version}-linux-x86_64.AppImage"
if ((!skip_appimage)); then
    appimagetool="$cache_dir/appimagetool-x86_64.AppImage"
    appimage_runtime="$cache_dir/runtime-x86_64"
    fetch "$APPIMAGETOOL_URL" "$appimagetool" "$APPIMAGETOOL_SHA256"
    fetch "$APPIMAGE_RUNTIME_URL" "$appimage_runtime" "$APPIMAGE_RUNTIME_SHA256"
    chmod 0755 "$appimagetool"
    rm -f -- "$appimage_path"
    ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 "$appimagetool" --runtime-file "$appimage_runtime" "$app_dir" "$appimage_path"
    chmod 0755 "$appimage_path"
fi

cp -- "$dosbox_source" "$compliance_dir/$DOSBOX_SOURCE"
cp -- "$root/LICENSE" "$compliance_dir/LICENSE-DOSSTATSPORT-MIT"
cp -- "$dosbox_work/LICENSE" "$compliance_dir/LICENSE-DOSBOX-STAGING"
cp -- "$root/packaging/LICENSE-APPIMAGE-RUNTIME" "$compliance_dir/LICENSE-APPIMAGE-RUNTIME"
cp -a -- "$dosbox_work/doc/licenses" "$compliance_dir/dosbox-third-party-licenses"

build_info="$compliance_dir/BUILD-INFO.txt"
cp -- "$app_dir/usr/share/dis-estadistica/BUILD-INFO" "$build_info"
ldd "$dosbox_work/dosbox" > "$compliance_dir/DOSBOX-RUNTIME-DEPENDENCIES.txt"

checksums="$output_dir/SHA256SUMS"
(
    cd "$output_dir"
    paths=("$portable_name.tar.xz" "compliance/$DOSBOX_SOURCE")
    ((!skip_appimage)) && paths+=("$(basename -- "$appimage_path")")
    sha256sum "${paths[@]}"
) > "$checksums"

printf '\nArtefactos construidos en %s:\n' "$output_dir"
printf '  %s\n' "$portable_archive"
((skip_appimage)) || printf '  %s\n' "$appimage_path"
printf '  %s\n' "$checksums"
printf '\nUso personal: no redistribuya artefactos que contienen DIS sin autorizacion.\n'
