# Screenshots

These images are referenced by the top-level `README.md` and `README.zh-CN.md`.

| File | What it should show | Status |
| --- | --- | --- |
| `menubar-icon.png` | A tight crop of the macOS menu bar with the Pi Web status icon in place (SF Symbol + the short `Pi` title, tinted by state). | Real capture. 160x76. |
| `menu-open.png` | The Pi Web dropdown menu actually open — the hero image of the README. | **Placeholder — replace with a real capture.** |
| `app-icon.png` | The app icon at 512x512, as rendered by Finder / Launchpad. | Real, generated from `Contents/Resources/PiWeb.icns`. |
| `image-20261019134737277.png` | The `pi-web` console UI opened by the launcher (top-of-README hero). | Real capture. 2440x1648. |
| `docks.png` | The Pi Web menu actually open, captured on a real desktop (top-of-README hero). | Real capture. 770x658. |

## Keeping the sizes reasonable

Git renders these at README width, so anything up to ~1440px wide is plenty.
Keep each file under about 1.5 MB; `sips` can downscale an oversized capture:

```sh
sips -Z 1440 big.png --out docs/images/image-20261019134737277.png
```

## Replacing the placeholder

`scripts/capture-screenshots.sh` automates as much as it can and prints
step-by-step instructions for the parts that need a human. In short:

1. Grant **Screen Recording** to your terminal app in
   System Settings → Privacy & Security → Screen Recording, then restart the
   terminal. `screencapture` fails with *"could not create image from display"*
   without it.
2. `./build.sh --run` to launch the app.
3. Launch it a **second** time — the already-running instance receives the
   `com.piweb.desktop.activate` distributed notification and pops its own menu.
   Capture immediately while the menu is open, then crop.
4. Overwrite `menu-open.png` and update the status column above.

Screenshots taken after a UI change should be updated in the same pull request.
