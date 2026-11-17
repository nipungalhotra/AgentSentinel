#!/bin/bash
# loggdin installer for macOS.
#
#   curl -fsSL https://loggdin.com/install.sh | bash
#
# Downloads the latest Loggdin.dmg from GitHub Releases, checks its SHA-256, copies Loggdin.app into
# /Applications (or ~/Applications without admin rights) and opens it. The app then puts the
# `loggdin` command on your PATH and asks which agents to connect. Nothing else on the Mac is changed.
#
# Options (environment): LOGGDIN_VERSION=1.2.1 to pick a release, LOGGDIN_DIR=/path to choose the folder,
# LOGGDIN_BASE_URL to download from a mirror or a local build folder (file:///…/dist).
set -euo pipefail

REPO="nipungalhotra/AgentSentinel"
say()  { printf '\033[1m%s\033[0m\n' "$*"; }
fail() { printf '\033[31mloggdin: %s\033[0m\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "this installer is for macOS. On Windows or Linux, use the portable zip from the release page."
major="$(sw_vers -productVersion | cut -d. -f1)"
[ "${major:-0}" -ge 14 ] || fail "loggdin needs macOS 14 (Sonoma) or later; this Mac has $(sw_vers -productVersion)."

if [ -n "${LOGGDIN_VERSION:-}" ]; then
  tag="v${LOGGDIN_VERSION#v}"
else
  tag="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)"
  [ -n "${tag}" ] || fail "couldn't find the latest release. Check your internet connection and try again."
fi
version="${tag#v}"
dmg="loggdin-v${version}.dmg"
base="${LOGGDIN_BASE_URL:-https://github.com/${REPO}/releases/download/${tag}}"

tmp="$(mktemp -d)"
trap 'hdiutil detach -quiet "${tmp}/mnt" 2>/dev/null || true; rm -rf "${tmp}"' EXIT

say "Downloading loggdin ${version}…"
curl -fL --progress-bar -o "${tmp}/${dmg}" "${base}/${dmg}" || fail "download failed (${base}/${dmg})."
curl -fsSL -o "${tmp}/${dmg}.sha256" "${base}/${dmg}.sha256" || fail "couldn't download the checksum file."
expected="$(awk '{print $1}' "${tmp}/${dmg}.sha256")"
actual="$(shasum -a 256 "${tmp}/${dmg}" | awk '{print $1}')"
[ -n "${expected}" ] && [ "${expected}" = "${actual}" ] || fail "checksum mismatch: the download is damaged or was changed. Nothing was installed."

dest="${LOGGDIN_DIR:-/Applications}"
if [ -z "${LOGGDIN_DIR:-}" ] && [ ! -w "${dest}" ]; then
  dest="${HOME}/Applications"   # no admin rights: install for this user only
fi
mkdir -p "${dest}"

hdiutil attach -quiet -nobrowse -readonly -mountpoint "${tmp}/mnt" "${tmp}/${dmg}" || fail "couldn't open the disk image."
[ -d "${tmp}/mnt/Loggdin.app" ] || fail "Loggdin.app is missing from the disk image."

# Quit a running copy so it can be replaced.
osascript -e 'tell application id "com.antigravity.loggdin" to quit' >/dev/null 2>&1 || true
pkill -f "Loggdin.app/Contents/MacOS/loggdin" 2>/dev/null || true
sleep 1

if [ -e "${dest}/Loggdin.app" ]; then
  if ! /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "${dest}/Loggdin.app/Contents/Info.plist" 2>/dev/null | grep -q "loggdin"; then
    fail "${dest}/Loggdin.app exists and isn't loggdin; leaving it alone."
  fi
  rm -rf "${dest}/Loggdin.app"
fi
say "Installing Loggdin.app into ${dest}…"
ditto "${tmp}/mnt/Loggdin.app" "${dest}/Loggdin.app"

# Agents run hooks with Python 3. Point out the one-time Apple install if it's missing.
has_python=1
if ! [ -x /opt/homebrew/bin/python3 ] && ! [ -x /usr/local/bin/python3 ] \
   && ! [ -x /Library/Frameworks/Python.framework/Versions/Current/bin/python3 ] \
   && ! xcode-select -p >/dev/null 2>&1; then
  has_python=0
fi

open "${dest}/Loggdin.app"
echo
say "✓ loggdin ${version} is installed and running (look for it in the menu bar)."
echo "  The app opens on Agent Integrations: connect the agents you use there,"
echo "  or in a new Terminal window run:  loggdin install"
if [ "${has_python}" = 0 ]; then
  echo
  say "One more step: install Python 3 (needed to connect agents)."
  echo "  Run:  xcode-select --install   (Apple's free command line tools, a few minutes)"
fi
