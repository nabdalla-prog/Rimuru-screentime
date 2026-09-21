#!/usr/bin/env bash
# Renders the popup on its own, with made-up data, and saves a screenshot.
#
#   tools/preview.sh [scenario] [out.png] [region]
#
# Examples:
#   tools/preview.sh today /tmp/today.png
#   tools/preview.sh year /tmp/year.png "20,50 500x760"
#   THEMES=/usr/share/omarchy/themes/white tools/preview.sh today /tmp/light.png
#
# It opens a small overlay window for a few seconds (needs Quickshell, grim and
# Omarchy's shell files) and never reads or writes your real history. See the
# comment at the top of tools/preview/shell.qml for the environment variables.
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
scenario="${1:-today}"
out="${2:-preview-$scenario.png}"
region="${3:-20,50 500x575}"

work="$(mktemp -d)"
trap 'kill "${pid:-0}" 2>/dev/null || true; rm -rf "$work"' EXIT

cp "$here/tools/preview/shell.qml" "$work/shell.qml"
ln -s /usr/share/omarchy/shell/Commons "$work/Commons"
ln -s "$here" "$work/plugin"

SCEN="$scenario" quickshell -p "$work" >"$work/log" 2>&1 &
pid=$!
sleep 3.5
grim -g "$region" "$out"
echo "saved $out"
