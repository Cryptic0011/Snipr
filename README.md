<p align="center">
  <img src="site/logo-mark.png" width="72" alt="">
</p>

<h1 align="center">Snipr</h1>

<p align="center">
  Keyboard-first screen capture for macOS — screenshots, recordings, OCR, and annotation, all local.
  <br>
  <a href="https://cryptic0011.github.io/Snipr/"><strong>Website</strong></a> ·
  <a href="https://github.com/Cryptic0011/Snipr/releases/latest"><strong>Download</strong></a>
</p>

---

Snipr is not trying to be the best screenshot tool on the Mac. It's an
**open-source, forkable alternative to the paid ones** — if a tool like
CleanShot X does everything you want, buy it. Snipr is for people who want the
core loop (capture → annotate → OCR → ship) without a subscription, an
account, or a cloud, and who want to be able to read, change, and rebuild the
tool they run on their screen.

<p align="center">
  <img src="site/dashboard.png" width="640" alt="The Snipr dashboard: quick capture actions on the left, recent captures on the right.">
</p>

## What it does

| | Default hotkey |
|---|---|
| Area capture with 8× loupe, live coordinates, edge snapping, typed dimensions | `⌘⇧4` |
| Window picker & full-screen capture at native Retina resolution | `⌘⇧5` |
| Scrolling capture — stitches a long page into one tall image | via capture toolbar |
| Screen recording (.mov, system audio, trim before save) | `⌘⇧6` |
| OCR any pixels straight to the clipboard | `⌘⇧O` |
| Color picker with hex/RGB/HSL output | `⌘⇧C` |
| Command palette | `⌘⇧Space` |
| Show the Stack | `⌘⇧S` |

Plus: annotation (arrows, shapes, blur, pixelate, step badges, text, crop,
undo/redo), pinned floating captures, the Stack (captures pile up in a corner
until you drag them out, batch-save, or combine to PDF), filename templates,
smart folders, and simple capture workflows. Every hotkey is rebindable in
Settings.

## Privacy

Everything stays on your Mac. No cloud upload, no account, no telemetry.
Sharing goes through the standard macOS share sheet. Updates come from
[Sparkle](https://sparkle-project.org) checked against a public key, and the
app is signed and notarized.

## Install

Grab the DMG from [the latest release](https://github.com/Cryptic0011/Snipr/releases/latest)
(or the [website](https://cryptic0011.github.io/Snipr/)), drag Snipr to
Applications, and grant Screen Recording permission on first capture.
Requires macOS 14+ (Apple Silicon).

## Build from source

```bash
git clone https://github.com/Cryptic0011/Snipr && cd Snipr
swift build          # or: swift test
./script/build_and_run.sh   # builds the .app bundle and launches it
```

Plain SwiftPM — no Xcode project. `HANDOFF.md` maps the architecture;
`RELEASING.md` covers signing, notarization, and shipping your own fork's
releases (you'll need your own Developer ID and Sparkle keys).

## License

[MIT](LICENSE). Fork it, rename it, ship it.
