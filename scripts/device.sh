#!/usr/bin/env bash
# Talks to Athena on a USB-connected iPhone with Developer Mode on (Xcode's devicectl).
#
#   scripts/device.sh autotest [--model ID]   launches Athena with --autotest: it downloads the model if
#                                             missing, loads it, asks the quick questions about two sample
#                                             messages, prints answers, timings and memory here, and exits.
#                                             IDs: h2o-lightning-4b, d1-2b, kev-0.8b, vllm-d3-edge, laya
#   scripts/device.sh files                   lists the models Athena keeps
set -euo pipefail

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

device="${DEVICE:-$(idevice_id -l | head -1)}"
[ -n "$device" ] || { echo "no iPhone on USB (plug it in and unlock it)" >&2; exit 1; }

# Impactor appends the team ID to the bundle ID, so look it up
xcrun devicectl device info apps --device "$device" --include-all-apps --json-output "$tmp/apps.json" >/dev/null
bundle="$(python3 -I -c '
import json, sys
apps = json.load(open(sys.argv[1]))["result"]["apps"]
ids = [a["bundleIdentifier"] for a in apps if a["bundleIdentifier"].startswith("dev.ehollbach.athena")]
print(ids[0] if ids else "")' "$tmp/apps.json")"
[ -n "$bundle" ] || { echo "Athena is not installed: install build/Athena.ipa with Impactor" >&2; exit 1; }

case "${1:-}" in
    autotest)
        shift
        xcrun devicectl device process launch --device "$device" --console --terminate-existing \
            "$bundle" --autotest "$@"
        ;;
    files)
        xcrun devicectl device info files --device "$device" --domain-type appDataContainer \
            --domain-identifier "$bundle" --subdirectory Library/Application\ Support/models
        ;;
    *)
        sed -n '2,9p' "$0" >&2
        exit 2
        ;;
esac
