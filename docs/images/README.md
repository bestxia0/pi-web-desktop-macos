# Screenshots

Referenced by the top-level `README.md` and `README.zh-CN.md`. `make check-docs`
fails if a file here is neither referenced by a README nor listed below, or if
the two READMEs reference different sets of images.

| File | What it shows | Status |
| --- | --- | --- |
| `menubar-icon.png` | A tight crop of the macOS menu bar with the Pi Web status icon in place (SF Symbol plus the short `Pi` title, tinted by state). | Real capture, 160x76. Referenced by both READMEs. |
| `menu.png` | The Pi Web dropdown menu, captured with the rounded panel and drop shadow intact. | Real capture, 770x658, taken on **v0.5.0** — it predates the tab rows (`新建标签页`, `标签页`) and `右侧 Option 唤起窗口` added in 0.6.0/0.7.0. Referenced by both READMEs. Recapture when the menu changes. |
| `pi-web-console.png` | The `pi-web` console UI rendered in one of the launcher's own native `WKWebView` tabs. | Real capture, 2440x1648. Referenced by both READMEs. |
| `app-icon.png` | The app icon at 512x512 as Finder / Launchpad render it. | Generated from `Contents/Resources/PiWeb.icns` by `scripts/capture-screenshots.sh`. Not referenced by the READMEs. |

## Keeping the sizes reasonable

Git renders these at README width, so anything up to ~1440px wide is plenty.
Keep each file under about 1.5 MB; `sips` can downscale an oversized capture:

```sh
sips -Z 1440 big.png --out docs/images/pi-web-console.png
```

## Recapturing

`scripts/capture-screenshots.sh` automates the parts it can (the app icon, and a
full-screen shot it leaves for you to crop) and prints instructions for the
rest. Two images need a human:

1. Grant **Screen Recording** to your terminal app in
   System Settings → Privacy & Security → Screen Recording, then restart the
   terminal. `screencapture` fails with *"could not create image from display"*
   without it.
2. `./build.sh --run` to launch the app, then launch it a **second** time: the
   running instance receives the `com.piweb.desktop.activate` distributed
   notification and pops its own menu. Capture immediately while it is open,
   crop to the panel, and overwrite `menu.png`.
3. Open a tab and capture the pi-web console for `pi-web-console.png`.

Update the version note in the table above (and the caption in both READMEs)
when the menu or the console UI changes.
