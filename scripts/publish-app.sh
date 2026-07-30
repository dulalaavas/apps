#!/usr/bin/env bash
#
# Publish an app to the "Aavash's Apps" source.
#
#   ./scripts/publish-app.sh /path/to/MyApp.ipa
#   ./scripts/publish-app.sh /path/to/MyApp.ipa --notes "What changed in this version"
#
# Reads the bundle id, version, name and minimum iOS out of the IPA itself,
# uploads it as a release on this repo, and updates source.json — adding the app
# if it is new, or prepending a version if it already exists.
#
# The size and SHA-256 in source.json must match the published file byte for
# byte or installs fail, so both are always derived from the artifact here.
#
# For a brand-new app the entry lands with a placeholder subtitle/description;
# edit source.json afterwards and drop artwork in assets/<slug>/.

set -euo pipefail

IPA="${1:-}"
NOTES=""
if [[ "${2:-}" == "--notes" ]]; then NOTES="${3:-}"; fi

if [[ -z "$IPA" || ! -f "$IPA" ]]; then
    echo "usage: $0 <path-to.ipa> [--notes \"description\"]" >&2
    exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SLUG_REPO="dulalaavas/apps"
RAW="https://raw.githubusercontent.com/$SLUG_REPO/main"
cd "$REPO_ROOT"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
unzip -q "$IPA" -d "$WORK"

APP_DIR="$(find "$WORK/Payload" -maxdepth 1 -name '*.app' | head -1)"
[[ -n "$APP_DIR" ]] || { echo "no Payload/*.app inside that IPA" >&2; exit 1; }
PLIST="$APP_DIR/Info.plist"

read_plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST" 2>/dev/null || true; }

BUNDLE_ID="$(read_plist CFBundleIdentifier)"
VERSION="$(read_plist CFBundleShortVersionString)"
MIN_OS="$(read_plist MinimumOSVersion)"
NAME="$(read_plist CFBundleDisplayName)"
[[ -n "$NAME" ]] || NAME="$(read_plist CFBundleName)"
[[ -n "$BUNDLE_ID" && -n "$VERSION" ]] || { echo "IPA is missing a bundle id or version" >&2; exit 1; }

SLUG="$(echo "${BUNDLE_ID##*.}" | tr '[:upper:]' '[:lower:]')"
TAG="$SLUG-v$VERSION"
ASSET="$(basename "$IPA")"
SIZE=$(stat -f%z "$IPA")
SHA=$(shasum -a 256 "$IPA" | cut -d' ' -f1)
DATE=$(date -u +%Y-%m-%dT00:00:00Z)
URL="https://github.com/$SLUG_REPO/releases/download/$TAG/$ASSET"

echo "==> $NAME $VERSION ($BUNDLE_ID), min iOS ${MIN_OS:-unknown}"
echo "    $SIZE bytes, sha256 $SHA"

# Use hand-placed artwork if present; otherwise seed an icon from the bundle.
mkdir -p "assets/$SLUG"
if [[ ! -f "assets/$SLUG/icon.png" ]]; then
    BUNDLE_ICON="$(find "$APP_DIR" -maxdepth 1 -name 'AppIcon*.png' | sort | tail -1)"
    if [[ -n "$BUNDLE_ICON" ]]; then
        cp "$BUNDLE_ICON" "assets/$SLUG/icon.png"
        echo "    seeded assets/$SLUG/icon.png from the app bundle (swap in a 1024px one)"
    fi
fi

echo "==> Publishing release $TAG"
if gh release view "$TAG" --repo "$SLUG_REPO" >/dev/null 2>&1; then
    gh release upload "$TAG" "$IPA" --repo "$SLUG_REPO" --clobber
else
    gh release create "$TAG" "$IPA" --repo "$SLUG_REPO" \
        --title "$NAME $VERSION" \
        --notes "${NOTES:-$NAME $VERSION.} Requires iOS ${MIN_OS:-17.0} or later. Install through the Aavash's Apps source: $RAW/source.json — the IPA is unsigned, so your sideloading tool signs it with your own certificate."
fi

echo "==> Updating source.json"
NAME="$NAME" BUNDLE_ID="$BUNDLE_ID" VERSION="$VERSION" MIN_OS="${MIN_OS:-17.0}" \
SIZE="$SIZE" SHA="$SHA" DATE="$DATE" URL="$URL" SLUG="$SLUG" RAW="$RAW" NOTES="$NOTES" \
python3 - source.json <<'PY'
import collections, json, os, sys

path = sys.argv[1]
with open(path) as f:
    source = json.load(f, object_pairs_hook=collections.OrderedDict)

env = os.environ
notes = env["NOTES"] or f"{env['NAME']} {env['VERSION']}."

entry = collections.OrderedDict([
    ("version", env["VERSION"]),
    ("date", env["DATE"]),
    ("localizedDescription", notes),
    ("downloadURL", env["URL"]),
    ("size", int(env["SIZE"])),
    ("sha256", env["SHA"]),
    ("minOSVersion", env["MIN_OS"]),
])

app = next((a for a in source["apps"]
            if a["bundleIdentifier"] == env["BUNDLE_ID"]), None)

if app is None:
    icon = f"{env['RAW']}/assets/{env['SLUG']}/icon.png"
    app = collections.OrderedDict([
        ("name", env["NAME"]),
        ("bundleIdentifier", env["BUNDLE_ID"]),
        ("developerName", "Aavash Dulal"),
        ("subtitle", f"{env['NAME']} for iOS."),
        ("localizedDescription", notes),
        ("iconURL", icon),
        ("tintColor", "0B6B5D"),
        ("category", "utilities"),
        ("screenshots", []),
        ("screenshotURLs", []),
        ("versions", []),
        ("appPermissions", collections.OrderedDict([
            ("entitlements", []), ("privacy", collections.OrderedDict()),
        ])),
    ])
    source["apps"].append(app)
    print(f"    added a new app entry — edit its subtitle/description in source.json")

# Newest first; a re-publish of the same version replaces it.
app["versions"] = [entry] + [v for v in app.get("versions", [])
                             if v["version"] != entry["version"]]

# Mirror onto the legacy top-level fields older clients still read.
app["version"] = entry["version"]
app["versionDate"] = entry["date"]
app["versionDescription"] = entry["localizedDescription"]
app["downloadURL"] = entry["downloadURL"]
app["size"] = entry["size"]
app["minOSVersion"] = entry["minOSVersion"]

with open(path, "w") as f:
    json.dump(source, f, indent=2, ensure_ascii=False)
    f.write("\n")
PY

git add source.json "assets/$SLUG" 2>/dev/null || git add source.json
git commit -q -m "$NAME $VERSION"
git push -q origin main

echo "==> Done. Source: $RAW/source.json"
