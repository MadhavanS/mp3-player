#!/usr/bin/env bash
# Regenerate assets/app_icon.png from the SVG source, then refresh launcher icons.
set -euo pipefail
cd "$(dirname "$0")/.."
npx --yes @resvg/resvg-js-cli assets/app_icon_liquid_m_reverted.svg assets/app_icon.png
cp assets/app_icon.png assets/app_icon_source.png
dart run flutter_launcher_icons
