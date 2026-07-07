# Releasing Snipr

One command, from a clean working tree on `main`:

```bash
./script/release.sh 0.2.0
```

That runs the tests, builds a release-config app, signs it (Developer ID +
hardened runtime, including Sparkle's nested XPC services / Autoupdate /
Updater.app), builds the DMG, notarizes and staples it, signs the update with
the Sparkle EdDSA key, inserts an `<item>` into `appcast.xml`, commits, tags
`v0.2.0`, pushes, and creates the GitHub release with the DMG attached.
Installed copies see the update via Sparkle within a few minutes (raw.githubusercontent
caches ~5 min).

## How updates reach users

- Feed: `https://raw.githubusercontent.com/Cryptic0011/Snipr/main/appcast.xml`
  (`SUFeedURL` in the app's Info.plist, written by `script/build_and_run.sh`).
- DMGs are GitHub release assets: `…/releases/download/v<version>/Snipr-<version>.dmg`.
- Sparkle verifies each download against `SUPublicEDKey`
  (`GPa3gezkwPZ2JAkqkXxa3DDSirwWVGd7kr1/H1Uu0sY=`).

## Machine-local prerequisites (all provisioned on Grayson's Mac, July 2026)

Releasing from a different machine needs these three moved over:

1. **Developer ID Application: Grayson Patterson (4Z9B3RLAJ2)** — login keychain.
2. **notarytool credentials** — keychain profile `snipr-notary`
   (`xcrun notarytool store-credentials snipr-notary --apple-id … --team-id 4Z9B3RLAJ2 --password <app-specific>`).
3. **Sparkle EdDSA private key** — login keychain item "Private key for signing
   Sparkle updates". Losing it means shipped apps reject all future updates;
   export/back it up via Keychain Access. The public half is hardcoded in
   `script/build_and_run.sh`.

`script/.sparkle-tools/` (sign_update etc.) is gitignored; `release.sh`
re-downloads it automatically if missing.

## Version numbers

Plain semver strings (`0.2.0`). `CFBundleVersion` and
`CFBundleShortVersionString` are both set to the release version by
`build_and_run.sh`; Sparkle compares them numerically. Never reuse or lower a
version.

## Troubleshooting

- **Notarization Invalid** → `xcrun notarytool log <submission-id> --keychain-profile snipr-notary`.
  Usual cause: something in the bundle unsigned or missing hardened runtime —
  check the nested-signing block in `script/build_dmg.sh`.
- **Sparkle says update is improperly signed** → the appcast `sparkle:edSignature`
  doesn't match the uploaded DMG. Never edit a DMG after `sign_update`; re-run
  the release with a bumped version.
- **`release.sh` refuses to run** → dirty tree or tag already exists; both are
  guards, not bugs.
