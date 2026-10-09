# Aavash's Apps

A personal AltStore-format source for the iOS apps I build. Add this URL in **LiveContainer**,
**AltStore**, or **SideStore**:

```
https://raw.githubusercontent.com/dulalaavas/apps/main/source.json
```

Every app here is **unsigned** — your sideloading tool signs it with your own certificate.

## Apps

| App | Version | Requires | Source |
|---|---|---|---|
| **Aware** — habits, mood, and journal | 1.2 | iOS 17+ | [dulalaavas/Aware](https://github.com/dulalaavas/Aware) |
| **Pocket Watch** — expense tracker built around Spaces | 1.0 | iOS 17+ | private |
| **Dsgtify** — Spotify with a Liquid Glass soul | 0.22.0 | iOS 16.1+ | [dulalaavas/spoti.pw](https://github.com/dulalaavas/spoti.pw) |

## Why this repo exists

The source manifest, the app artwork, and every published IPA live here rather than in each
app's own repo. That way an app repo can be private, get renamed, or disappear entirely
without breaking installs — GitHub serves no public raw or release-asset URLs for a private
repo, so anything the manifest points at has to be hosted somewhere reliably public. This is
that place.

## Adding a new app

```bash
./scripts/publish-app.sh /path/to/MyApp.ipa --notes "First release"
```

The script reads the bundle id, version, display name, and minimum iOS out of the IPA itself,
publishes it as a release here, and updates `source.json` — creating the app entry if it's new
or prepending a version if it already exists. It commits and pushes on its own.

Then polish the new entry, because the script can only guess at these:

1. Drop a 1024×1024 `icon.png` in `assets/<slug>/` (it seeds a small one from the app bundle).
2. Add screenshots to `assets/<slug>/` and list their raw URLs in `screenshots` /
   `screenshotURLs`.
3. Write a real `subtitle`, `localizedDescription`, `category`, and `tintColor`.

Publishing a new version of an existing app needs nothing but the script.

## Layout

```
source.json          the manifest clients read
assets/<slug>/       icon and screenshots per app
scripts/publish-app.sh
```

## Notes for future me

- `size` and `sha256` in the manifest must match the published IPA **byte for byte**, or
  installs fail with no useful error. Always let the script derive them.
- Each entry keeps both the modern `versions` array (newest first) and the legacy top-level
  `version` / `downloadURL` / `size` fields, because different clients read different ones.
- `raw.githubusercontent.com` caches for a few minutes. After pushing, give it a moment before
  concluding a client isn't seeing the change.
- Release tags are `<slug>-v<version>`, e.g. `pocketwatch-v1.0`.
