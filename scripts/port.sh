#!/usr/bin/env bash
# Wine-less Linux port of Grok Bot.
#
# The official product is a Windows NSIS installer. The JavaScript application
# (resources/app.asar) is platform-neutral and is copied unchanged. Everything
# that is a Windows PE binary — Grok Bot.exe, *.dll, and *.node addons — is
# replaced: official Electron linux-x64 for the shell, and Linux ELF rebuilds
# or prebuilds for the native addons.
set -euo pipefail

ELECTRON_VERSION_DEFAULT="42.1.0"
ELECTRON_VERSION="${ELECTRON_VERSION:-$ELECTRON_VERSION_DEFAULT}"
ELECTRON_ABI="${ELECTRON_ABI:-146}"
SQLITE_PREBUILD_VERSION="${SQLITE_PREBUILD_VERSION:-12.11.1}"

WIN32_TMPL="https://downloads.cursor.com/grokbot/stable/win32-x64/%s/Grok_Bot_%s_Setup.exe"
ELECTRON_TMPL="https://github.com/electron/electron/releases/download/v%s/electron-v%s-linux-x64.zip"
SEVENZIP_URL="https://github.com/ip7z/7zip/releases/download/25.01/7z2501-linux-x64.tar.xz"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
NATIVE_SRC="${SCRIPT_DIR}/native"
CACHE="${GROKBOT_CACHE:-${REPO_ROOT}/.cache}"
OUTDIR="${GROKBOT_OUTDIR:-${REPO_ROOT}/dist}"

if [[ -x /usr/bin/python3.12 ]]; then
  export PYTHON=/usr/bin/python3.12
  export npm_config_python=/usr/bin/python3.12
fi

log() { printf '%s\n' "$*" >&2; }
die() { log "error: $*"; exit 1; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [options] <version>

Options:
  --electron-version <ver>  Electron linux-x64 release (default: ${ELECTRON_VERSION_DEFAULT})
  --electron-abi <n>        NODE_MODULE_VERSION for prebuilds (default: ${ELECTRON_ABI})
  -h, --help                Show this help

Example:
  $(basename "$0") 0.24.0
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --electron-version)
        ELECTRON_VERSION="${2:?}"
        shift 2
        ;;
      --electron-abi)
        ELECTRON_ABI="${2:?}"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      -*)
        die "unknown option $1"
        ;;
      *)
        break
        ;;
    esac
  done
  [[ $# -eq 1 ]] || { usage >&2; die "exactly one <version> argument is required"; }
  GROK_VERSION="$1"
  [[ "${GROK_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version '${GROK_VERSION}' is not x.y.z"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || return 1
}

check_prereqs() {
  local missing=()
  for c in curl unzip node npm npx tar g++ make; do
    need_cmd "$c" || missing+=("$c")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    die "missing tools: ${missing[*]}
hint: install curl unzip nodejs npm build-essential python3"
  fi
}

resolve_7z() {
  if need_cmd 7z; then printf '%s' 7z; return; fi
  if need_cmd 7za; then printf '%s' 7za; return; fi
  if need_cmd 7zz; then printf '%s' 7zz; return; fi
  local bundled="${CACHE}/tools/7zz"
  if [[ -x "${bundled}" ]]; then
    printf '%s' "${bundled}"
    return
  fi
  log "system 7z not found — downloading 7-Zip 25.01 linux-x64"
  mkdir -p "${CACHE}/tools"
  local txz="${CACHE}/tools/7z-linux-x64.tar.xz"
  curl --fail --location --retry 3 --connect-timeout 15 --max-time 120 \
    -o "${txz}" "${SEVENZIP_URL}"
  tar -xJf "${txz}" -C "${CACHE}/tools" 7zz
  chmod +x "${bundled}"
  printf '%s' "${bundled}"
}

download() {
  local url="$1" dest="$2"
  mkdir -p "$(dirname "${dest}")"
  if [[ -s "${dest}" ]]; then
    log "reusing cached $(basename "${dest}")"
    return 0
  fi
  log "downloading ${url}"
  local tmp="${dest}.partial"
  curl --fail --location --retry 3 --retry-delay 2 \
    --connect-timeout 20 --max-time 600 \
    -o "${tmp}" "${url}"
  mv "${tmp}" "${dest}"
}

is_pe() {
  # MZ header
  [[ "$(head -c 2 "$1" 2>/dev/null || true)" == "MZ" ]]
}

is_elf() {
  [[ "$(od -An -tx1 -N4 "$1" 2>/dev/null | tr -d ' \n')" == "7f454c46" ]]
}

extract_windows_payload() {
  local installer="$1" dest="$2"
  local nsis="${WORKDIR}/nsis"
  mkdir -p "${nsis}" "${dest}"
  log "extracting NSIS installer (no Wine)"
  "${SEVEN_ZIP}" x -y "-o${nsis}" "${installer}" >/dev/null

  local archive
  archive="$(find "${nsis}" -type f \( -name 'app-64.7z' -o -name 'app-32.7z' \) -print -quit || true)"
  [[ -n "${archive}" ]] || {
    find "${nsis}" -maxdepth 3 >&2
    die "no nested app-64.7z found inside the installer"
  }
  local magic
  magic="$(od -An -tx1 -N6 "${archive}" | tr -d ' \n')"
  [[ "${magic}" == "377abcaf271c" ]] || die "${archive} is not a 7z archive (got ${magic})"
  log "found payload ${archive}"
  "${SEVEN_ZIP}" x -y "-o${dest}" "${archive}" >/dev/null

  if [[ ! -f "${dest}/resources/app.asar" ]]; then
    if [[ -f "${dest}/app.asar" ]]; then
      mkdir -p "${dest}/resources"
      mv "${dest}/app.asar" "${dest}/resources/app.asar"
      [[ -d "${dest}/app.asar.unpacked" ]] && mv "${dest}/app.asar.unpacked" "${dest}/resources/"
    else
      die "app.asar missing after extraction"
    fi
  fi
}

detect_electron_from_exe() {
  local exe="$1"
  need_cmd strings || return 0
  local found
  found="$(strings "${exe}" | grep -oE 'Electron/[0-9]+\.[0-9]+\.[0-9]+' | head -n1 | cut -d/ -f2 || true)"
  if [[ -n "${found}" ]]; then
    log "Windows binary reports Electron ${found}"
    ELECTRON_VERSION="${found}"
  fi
}

stage_linux_app() {
  local win_app="$1" electron_dir="$2" staged="$3"
  mkdir -p "${staged}/resources"

  cp "${electron_dir}/electron" "${staged}/grok-bot"
  chmod 755 "${staged}/grok-bot"

  local f
  for f in chrome-sandbox chrome_crashpad_handler \
           libEGL.so libGLESv2.so libffmpeg.so libvk_swiftshader.so libvulkan.so.1 \
           vk_swiftshader_icd.json icudtl.dat snapshot_blob.bin v8_context_snapshot.bin \
           LICENSE.electron.txt LICENSES.chromium.html; do
    [[ -e "${electron_dir}/${f}" ]] && cp -a "${electron_dir}/${f}" "${staged}/"
  done
  [[ -d "${electron_dir}/locales" ]] && cp -a "${electron_dir}/locales" "${staged}/"
  shopt -s nullglob
  for f in "${electron_dir}"/*.pak "${electron_dir}"/*.so "${electron_dir}"/*.so.*; do
    cp -a "${f}" "${staged}/"
  done
  shopt -u nullglob

  # Application core: copy the Windows resources tree as-is, then we only
  # replace PE natives in a later step. app.asar is JS and is never rewritten
  # except to keep packed natives in sync with the unpacked tree.
  cp -a "${win_app}/resources/app.asar" "${staged}/resources/app.asar"
  if [[ -d "${win_app}/resources/app.asar.unpacked" ]]; then
    cp -a "${win_app}/resources/app.asar.unpacked" "${staged}/resources/"
  fi
  for extra in "${win_app}/resources"/*; do
    [[ -e "${extra}" ]] || continue
    local base
    base="$(basename "${extra}")"
    case "${base}" in
      app.asar|app.asar.unpacked|elevate.exe) continue ;;
      *.exe) continue ;;
    esac
    cp -a "${extra}" "${staged}/resources/"
  done

  find "${staged}" -type d -exec chmod 755 {} +
  find "${staged}" -type f -exec chmod 644 {} +
  chmod 755 "${staged}/grok-bot"
  [[ -f "${staged}/chrome-sandbox" ]] && chmod 4755 "${staged}/chrome-sandbox" || true
  [[ -f "${staged}/chrome_crashpad_handler" ]] && chmod 755 "${staged}/chrome_crashpad_handler" || true
  find "${staged}" -type f \( -name '*.so' -o -name '*.so.*' -o -name '*.node' \) -exec chmod 755 {} +
}

npm_pack_extract() {
  local spec="$1" dest="$2"
  mkdir -p "${dest}"
  local tmp
  tmp="$(mktemp -d "${WORKDIR}/npm-XXXXXX")"
  (cd "${tmp}" && npm pack --ignore-scripts "${spec}" >/dev/null)
  local tgz
  tgz="$(ls "${tmp}"/*.tgz | head -n1)"
  tar -xzf "${tgz}" -C "${tmp}"
  cp -a "${tmp}/package/." "${dest}/"
  rm -rf "${tmp}"
}

place_file() {
  local src="$1" dest="$2"
  mkdir -p "$(dirname "${dest}")"
  cp -f "${src}" "${dest}"
  chmod 755 "${dest}"
}

rebuild_cursor_proclist() {
  local mod="$1"
  log "rebuilding cursor-proclist from Linux /proc sources"
  mkdir -p "${mod}/src"
  cp -f "${NATIVE_SRC}/cursor_proclist.h" "${mod}/src/"
  cp -f "${NATIVE_SRC}/cursor_proclist.cc" "${mod}/src/"
  cp -f "${NATIVE_SRC}/cursor_proclist_linux.cc" "${mod}/src/"
  cp -f "${NATIVE_SRC}/binding.gyp" "${mod}/binding.gyp"
  rm -rf "${mod}/build"
  (
    cd "${mod}"
    npx --yes node-gyp rebuild --release \
      --target="${ELECTRON_VERSION}" \
      --arch=x64 \
      --dist-url=https://electronjs.org/headers \
      --runtime=electron
  )
  local built="${mod}/build/Release/cursor_proclist.node"
  [[ -f "${built}" ]] || die "cursor-proclist rebuild produced no .node"
  if is_pe "${built}"; then
    die "cursor-proclist rebuild is still a Windows PE"
  fi
}

install_better_sqlite() {
  local mod="$1"
  local url="https://github.com/WiseLibs/better-sqlite3/releases/download/v${SQLITE_PREBUILD_VERSION}/better-sqlite3-v${SQLITE_PREBUILD_VERSION}-electron-v${ELECTRON_ABI}-linux-x64.tar.gz"
  local tgz="${CACHE}/better-sqlite3-v${SQLITE_PREBUILD_VERSION}-electron-v${ELECTRON_ABI}-linux-x64.tar.gz"
  log "installing better-sqlite3 electron-v${ELECTRON_ABI} linux-x64 prebuild (${SQLITE_PREBUILD_VERSION})"
  download "${url}" "${tgz}"
  local tmp
  tmp="$(mktemp -d "${WORKDIR}/sqlite-XXXXXX")"
  tar -xzf "${tgz}" -C "${tmp}"
  local src
  src="$(find "${tmp}" -name better_sqlite3.node -print -quit || true)"
  [[ -n "${src}" ]] || die "better_sqlite3.node missing from prebuild tarball"
  rm -rf "${mod}/build"
  place_file "${src}" "${mod}/build/Release/better_sqlite3.node"
  if is_pe "${mod}/build/Release/better_sqlite3.node"; then
    die "better-sqlite3 prebuild is PE"
  fi
  rm -rf "${tmp}"
}

install_tree_sitter() {
  local mod="$1"
  log "fetching tree-sitter@0.21.1 linux prebuild / source"
  local tmp="${WORKDIR}/tree-sitter-npm"
  rm -rf "${tmp}"
  npm_pack_extract "tree-sitter@0.21.1" "${tmp}"
  local pre
  pre="$(find "${tmp}/prebuilds/linux-x64" -name '*.node' -print -quit 2>/dev/null || true)"
  if [[ -n "${pre}" ]]; then
    mkdir -p "${mod}/prebuilds/linux-x64"
    cp -f "${pre}" "${mod}/prebuilds/linux-x64/"
    # asar lists build/Release as unpacked; deleting that file makes Electron
    # look on disk, miss it, and crash. Replace the PE in place instead.
    place_file "${pre}" "${mod}/build/Release/tree_sitter_runtime_binding.node"
    log "installed $(basename "${pre}") for tree-sitter"
    return
  fi
  log "no tree-sitter linux prebuild in npm pack — rebuilding"
  cp -a "${tmp}/." "${mod}/"
  (
    cd "${mod}"
    NODE_PATH="${DEPS_ROOT}:${DEPS_ROOT}/node-addon-api:${NODE_PATH:-}" \
      npx --yes @electron/rebuild --version "${ELECTRON_VERSION}" --module-dir "${mod}"
  )
}

install_tree_sitter_bash() {
  local mod="$1"
  log "fetching tree-sitter-bash@0.21.0 linux prebuild"
  local tmp="${WORKDIR}/tree-sitter-bash-npm"
  rm -rf "${tmp}"
  npm_pack_extract "tree-sitter-bash@0.21.0" "${tmp}"
  mkdir -p "${mod}/prebuilds/linux-x64"
  local pre
  pre="$(find "${tmp}/prebuilds/linux-x64" -name '*.node' -print -quit 2>/dev/null || true)"
  [[ -n "${pre}" ]] || die "tree-sitter-bash npm pack has no linux-x64 prebuild"
  cp -f "${pre}" "${mod}/prebuilds/linux-x64/"
  place_file "${pre}" "${mod}/build/Release/tree_sitter_bash_binding.node"
  log "installed $(basename "${pre}") for tree-sitter-bash"
}

install_whichlang() {
  local mod="$1"
  log "fetching whichlang-node-linux-x64-gnu@0.2.1"
  local tmp="${WORKDIR}/whichlang-npm"
  rm -rf "${tmp}"
  npm_pack_extract "whichlang-node-linux-x64-gnu@0.2.1" "${tmp}"
  local nodef
  nodef="$(find "${tmp}" -name 'whichlang-node.linux-x64-gnu.node' -print -quit || true)"
  [[ -n "${nodef}" ]] || die "whichlang linux .node missing from npm pack"
  place_file "${nodef}" "${mod}/whichlang-node.linux-x64-gnu.node"
}

compile_tree_chunk_stub() {
  local mod="$1"
  log "compiling N-API stub for private @anysphere/tree-chunk-napi"
  local inc=""
  local node_bin cand
  node_bin="$(readlink -f "$(command -v node)")"
  for cand in \
    "$(dirname "$(dirname "${node_bin}")")/include/node" \
    "$(dirname "$(dirname "$(command -v node)")")/include/node" \
    /usr/include/node \
    /usr/local/include/node; do
    if [[ -f "${cand}/node_api.h" ]]; then
      inc="${cand}"
      break
    fi
  done
  [[ -n "${inc}" ]] || die "node_api.h not found (need Node headers next to the node binary)"
  local dest="${mod}/tree-chunk-napi.linux-x64-gnu.node"
  g++ -shared -fPIC -s -O2 -std=c++17 \
    -Wl,-z,noexecstack -Wl,--build-id=none \
    -I"${inc}" \
    "${NATIVE_SRC}/tree_chunk_stub.cc" -o "${dest}"
  chmod 755 "${dest}"
  if is_pe "${dest}"; then
    die "tree-chunk stub is PE"
  fi
}

assert_no_loadable_pe() {
  local root="$1"
  local live=""
  local f
  while IFS= read -r f; do
    [[ -z "${f}" ]] && continue
    is_pe "${f}" || continue
    case "${f}" in
      */prebuilds/win32-*|*.win32-*.node) continue ;;
    esac
    live+="${f}"$'\n'
  done < <(find "${root}" -type f -name '*.node' -print)

  if [[ -n "${live}" ]]; then
    if [[ "${GROKBOT_ALLOW_BROKEN_NATIVE:-}" == "1" ]]; then
      log "warn: loadable Windows .node files remain (override active):"
      printf '%s' "${live}" >&2
      return 0
    fi
    log "error: loadable .node files still have an MZ header:"
    printf '%s' "${live}" >&2
    die "native rebuild left Windows binaries that Linux would dlopen"
  fi
  log "no loadable Windows .node files remain"
}

repack_asar_natives() {
  local staged="$1"
  local asar="${staged}/resources/app.asar"
  local unpacked="${staged}/resources/app.asar.unpacked"
  local win_res="${WORKDIR}/win-app/resources"
  local work="${WORKDIR}/asar-repack"
  rm -rf "${work}"
  mkdir -p "${work}"

  log "repacking app.asar so Linux .node files are visible through the asar index"
  # Extract using the original Windows asar + matching unpacked sibling.
  # Extracting the staged asar fails once we have added/removed overlay files.
  if [[ ! -f "${win_res}/app.asar" ]]; then
    log "warn: original Windows asar missing — leaving staged asar as-is"
    return 0
  fi
  cp "${win_res}/app.asar" "${work}/app.asar"
  cp -a "${win_res}/app.asar.unpacked" "${work}/app.asar.unpacked"
  if ! npx --yes @electron/asar extract "${work}/app.asar" "${work}/src"; then
    log "warn: asar extract failed — unpacked tree still has the Linux natives"
    return 0
  fi

  local f rel
  while IFS= read -r f; do
    is_elf "${f}" || continue
    rel="${f#"${unpacked}/"}"
    mkdir -p "${work}/src/$(dirname "${rel}")"
    cp -f "${f}" "${work}/src/${rel}"
  done < <(find "${unpacked}" -type f -name '*.node' -print)

  while IFS= read -r f; do
    if is_pe "${f}"; then
      rm -f "${f}"
    fi
  done < <(find "${work}/src" -type f -name '*.node' -print)

  if ! npx --yes @electron/asar pack "${work}/src" "${work}/out.asar" --unpack "*.node"; then
    log "warn: asar pack failed — runtime will use app.asar.unpacked"
    return 0
  fi
  cp -f "${work}/out.asar" "${asar}"
  if [[ -d "${work}/out.asar.unpacked" ]]; then
    rm -rf "${unpacked}"
    cp -a "${work}/out.asar.unpacked" "${unpacked}"
  fi
  log "repacked app.asar ($(du -h "${asar}" | cut -f1))"
}

make_tarball() {
  local staged="$1" name="$2"
  mkdir -p "${OUTDIR}"
  local tarpath="${OUTDIR}/${name}.tar.gz"
  tar -czf "${tarpath}" -C "$(dirname "${staged}")" "$(basename "${staged}")"
  log "tarball $(du -h "${tarpath}" | cut -f1)  ${tarpath}"
  printf '%s\n' "${tarpath}"
}

extract_icon() {
  local staged="$1" dest="$2"
  local asar="${staged}/resources/app.asar"
  local unpacked_icon
  unpacked_icon="$(find "${staged}/resources/app.asar.unpacked" -name 'app-icon*.png' -print -quit 2>/dev/null || true)"
  if [[ -n "${unpacked_icon}" ]]; then
    cp "${unpacked_icon}" "${dest}"
    return 0
  fi
  local listed
  listed="$(npx --yes @electron/asar list "${asar}" 2>/dev/null | grep -E 'app-icon.*\.png$' | head -n1 || true)"
  if [[ -n "${listed}" ]]; then
    local tmp="${WORKDIR}/icon-extract"
    mkdir -p "${tmp}"
    # extract-file writes <basename> into the current directory
    if (cd "${tmp}" && npx --yes @electron/asar extract-file "${asar}" "${listed#/}" >/dev/null); then
      local extracted
      extracted="$(find "${tmp}" -name '*.png' -print -quit || true)"
      if [[ -n "${extracted}" ]]; then
        cp "${extracted}" "${dest}"
        return 0
      fi
    fi
  fi
  return 1
}

make_appimage() {
  local staged="$1" version="$2"
  if ! need_cmd mksquashfs; then
    log "skipping AppImage (mksquashfs / squashfs-tools not installed)"
    return 0
  fi
  local appdir="${WORKDIR}/AppDir"
  local image="${OUTDIR}/Grok_Bot_${version}_x86_64.AppImage"
  rm -rf "${appdir}"
  mkdir -p "${appdir}/usr/bin" \
           "${appdir}/usr/share/applications" \
           "${appdir}/usr/share/icons/hicolor/256x256/apps"
  cp -a "${staged}/." "${appdir}/usr/bin/"

  if extract_icon "${staged}" "${appdir}/grok-bot.png" && [[ -s "${appdir}/grok-bot.png" ]]; then
    cp "${appdir}/grok-bot.png" "${appdir}/.DirIcon"
    cp "${appdir}/grok-bot.png" "${appdir}/usr/share/icons/hicolor/256x256/apps/grok-bot.png"
  else
    log "warn: no app icon found — writing a 1x1 placeholder so appimagetool accepts the AppDir"
    python3 - "${appdir}/grok-bot.png" <<'PY'
import struct, zlib, sys
path = sys.argv[1]
def chunk(tag, data):
    return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)
raw = b'\x00' + b'\x00\x00\x00'  # filter 0 + one black RGB pixel
png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 1, 1, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b'')
open(path, 'wb').write(png)
PY
    cp "${appdir}/grok-bot.png" "${appdir}/.DirIcon"
  fi

  cat > "${appdir}/grok-bot.desktop" <<EOF
[Desktop Entry]
Name=Grok Bot
GenericName=Grok Bot
Comment=Grok Bot desktop (unofficial Linux port)
Exec=grok-bot --no-sandbox
Icon=grok-bot
Type=Application
Categories=Utility;
Terminal=false
StartupWMClass=Grok Bot
X-AppImage-Version=${version}
EOF
  cp "${appdir}/grok-bot.desktop" "${appdir}/usr/share/applications/grok-bot.desktop"

  # squashfs cannot preserve a root-owned setuid chrome-sandbox when we are
  # not root, so AppRun always passes --no-sandbox. Use the tarball if you
  # need a real Chromium sandbox.
  cat > "${appdir}/AppRun" <<'EOF'
#!/bin/sh
SELF="$(readlink -f "$0")"
HERE="${SELF%/*}"
export APPDIR="${HERE}"
exec "${HERE}/usr/bin/grok-bot" --no-sandbox "$@"
EOF
  chmod +x "${appdir}/AppRun"

  local tool=""
  if need_cmd appimagetool; then
    tool="$(command -v appimagetool)"
  else
    local ai="${WORKDIR}/appimagetool.AppImage"
    if curl --fail --location --retry 3 --max-time 180 \
         -o "${ai}" \
         "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"; then
      chmod +x "${ai}"
      tool="${ai}"
    fi
  fi
  if [[ -z "${tool}" ]]; then
    log "skipping AppImage (appimagetool unavailable)"
    return 0
  fi

  mkdir -p "${OUTDIR}"
  if ! (cd "${WORKDIR}" && ARCH=x86_64 "${tool}" "${appdir}" "${image}" >&2); then
    log "warn: appimagetool failed — tarball is still valid"
    rm -f "${image}"
    return 0
  fi
  chmod +x "${image}"
  log "AppImage $(du -h "${image}" | cut -f1)  ${image}"
  printf '%s\n' "${image}"
}

make_deb() {
  local staged="$1" version="$2"
  need_cmd dpkg-deb || { log "skipping .deb (dpkg-deb not installed)"; return 0; }
  local root="${WORKDIR}/deb"
  rm -rf "${root}"
  local installdir="${root}/opt/grok-bot"
  mkdir -p "${installdir}" "${root}/usr/bin" \
           "${root}/usr/share/applications" \
           "${root}/usr/share/doc/grok-bot" \
           "${root}/DEBIAN"
  cp -a "${staged}/." "${installdir}/"
  ln -s /opt/grok-bot/grok-bot "${root}/usr/bin/grok-bot"
  cat > "${root}/usr/share/applications/grok-bot.desktop" <<EOF
[Desktop Entry]
Name=Grok Bot
Comment=Grok Bot desktop (unofficial Linux port)
Exec=/opt/grok-bot/grok-bot --no-sandbox
Icon=grok-bot
Type=Application
Categories=Utility;
Terminal=false
EOF
  cat > "${root}/DEBIAN/control" <<EOF
Package: grok-bot
Version: ${version}-1
Section: utils
Priority: optional
Architecture: amd64
Maintainer: unofficial grok-bot linux packager
Depends: libgtk-3-0, libnotify4, libnss3, libxss1, libxtst6, xdg-utils, libatspi2.0-0, libuuid1, libsecret-1-0
Description: Unofficial Linux build of Grok Bot
 Wine-less port: official Windows app.asar fused with Electron ${ELECTRON_VERSION}.
 Grok Bot itself remains proprietary.
EOF
  cat > "${root}/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
if [ "$1" = configure ]; then
  if [ -f /opt/grok-bot/chrome-sandbox ]; then
    chown root:root /opt/grok-bot/chrome-sandbox || true
    chmod 4755 /opt/grok-bot/chrome-sandbox || true
  fi
fi
exit 0
EOF
  chmod 755 "${root}/DEBIAN/postinst"
  local deb="${OUTDIR}/grok-bot_${version}_amd64.deb"
  if dpkg-deb --build "${root}" "${deb}" >/dev/null; then
    log "deb $(du -h "${deb}" | cut -f1)  ${deb}"
    printf '%s\n' "${deb}"
  else
    log "warn: dpkg-deb failed"
  fi
}

main() {
  parse_args "$@"
  check_prereqs
  mkdir -p "${CACHE}" "${OUTDIR}"
  SEVEN_ZIP="$(resolve_7z)"

  WORKDIR="$(mktemp -d -t grokbot-port-XXXXXX)"
  trap 'if [[ -z "${GROKBOT_KEEP_WORKDIR:-}" ]]; then rm -rf "${WORKDIR}"; fi' EXIT

  log "Grok Bot ${GROK_VERSION}"
  log "Electron   ${ELECTRON_VERSION} (ABI ${ELECTRON_ABI})"
  log "work dir   ${WORKDIR}"

  local installer="${CACHE}/Grok_Bot_${GROK_VERSION}_Setup.exe"
  download "$(printf "${WIN32_TMPL}" "${GROK_VERSION}" "${GROK_VERSION}")" "${installer}"

  local win_app="${WORKDIR}/win-app"
  extract_windows_payload "${installer}" "${win_app}"

  if [[ "${ELECTRON_VERSION}" == "${ELECTRON_VERSION_DEFAULT}" ]]; then
    local exe
    exe="$(find "${win_app}" -maxdepth 1 -name '*.exe' -print -quit || true)"
    [[ -n "${exe}" ]] && detect_electron_from_exe "${exe}"
  fi

  local ezip="${CACHE}/electron-v${ELECTRON_VERSION}-linux-x64.zip"
  download "$(printf "${ELECTRON_TMPL}" "${ELECTRON_VERSION}" "${ELECTRON_VERSION}")" "${ezip}"
  local electron_dir="${WORKDIR}/electron"
  mkdir -p "${electron_dir}"
  unzip -q "${ezip}" -d "${electron_dir}"

  local name="Grok_Bot_${GROK_VERSION}_linux_x64"
  local staged="${WORKDIR}/${name}"
  stage_linux_app "${win_app}" "${electron_dir}" "${staged}"

  DEPS_ROOT="${staged}/resources/app.asar.unpacked/dist/deps"
  [[ -d "${DEPS_ROOT}" ]] || die "expected native deps at ${DEPS_ROOT}"

  install_better_sqlite "${DEPS_ROOT}/better-sqlite3"
  rebuild_cursor_proclist "${DEPS_ROOT}/cursor-proclist"
  install_tree_sitter "${DEPS_ROOT}/tree-sitter"
  install_tree_sitter_bash "${DEPS_ROOT}/tree-sitter-bash"
  install_whichlang "${DEPS_ROOT}/whichlang-node"
  compile_tree_chunk_stub "${DEPS_ROOT}/@anysphere/tree-chunk-napi"

  assert_no_loadable_pe "${staged}/resources/app.asar.unpacked"
  repack_asar_natives "${staged}"

  if [[ -f "${staged}/chrome-sandbox" ]]; then
    if [[ "$(id -u)" -eq 0 ]]; then
      chown root:root "${staged}/chrome-sandbox"
      chmod 4755 "${staged}/chrome-sandbox"
    else
      log "hint: after extracting the tarball, run:"
      log "      sudo chown root:root chrome-sandbox && sudo chmod 4755 chrome-sandbox"
      log "      or launch with ./grok-bot --no-sandbox"
    fi
  fi

  local artifacts=()
  artifacts+=("$(make_tarball "${staged}" "${name}")")
  local img
  img="$(make_appimage "${staged}" "${GROK_VERSION}" || true)"
  [[ -n "${img}" ]] && artifacts+=("${img}")
  local deb
  deb="$(make_deb "${staged}" "${GROK_VERSION}" || true)"
  [[ -n "${deb}" ]] && artifacts+=("${deb}")

  printf '%s\n' "${GROK_VERSION}" > "${REPO_ROOT}/VERSION"

  log ""
  log "build complete — Grok Bot ${GROK_VERSION} + Electron ${ELECTRON_VERSION}"
  local a
  for a in "${artifacts[@]}"; do
    log "  ${a}"
    printf '%s\n' "${a}"
  done
}

main "$@"
