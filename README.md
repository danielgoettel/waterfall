# Petal Strips

Calm falling petals in slim strips pinned to the edges of your screen, with your
work in the middle. The strips reserve their space like the Windows taskbar, so a
maximized window sits between them instead of covering them. Drag a strip's inner
edge to make it wider or narrower and the window beside it follows.

Runs on Windows 10 or 11 with Microsoft Edge or Google Chrome. Nothing is installed:
the strips are chromeless browser windows driven by one PowerShell script.

## Run

Right-click `sides.ps1` and choose **Run with PowerShell**, or from a terminal:

```
powershell -ExecutionPolicy Bypass -File sides.ps1                 # two strips on every monitor
powershell -ExecutionPolicy Bypass -File sides.ps1 -Mode Outer     # one strip at each far edge of the desktop
powershell -ExecutionPolicy Bypass -File sides.ps1 -SideWidth 350  # wider strips
powershell -ExecutionPolicy Bypass -File sides.ps1 -Close          # close everything
```

The script stays running in the background while the strips are open and exits
when they close.

## Settings

Hover over a strip and click the gear (or press `S`). The panel has a speed dial,
color palettes, and sliders for petal count, size, flutter, wind, and background.
Changes apply instantly to every strip and are remembered between runs.

## Files

- `sides.ps1` launches, places, and watches the strips.
- `wallpaper/index.html` is the finished single-file page (three.js embedded).
- `wallpaper/index-template.html` is the editable source. After changing it, run
  `build.ps1` to regenerate `wallpaper/index.html`.
- `wallpaper/vendor/three.min.js` is three.js r158 (MIT, see `LICENSE-three.txt`).

## How it works

Each strip is registered with Windows as an app bar, which shrinks the work area
so maximized windows avoid it. The browser's title bar is pushed just above the
top of the screen, and the invisible resize border Windows adds to every window is
measured and compensated so the petals reach exactly to the screen edge. While a
strip is being dragged, the maximized window next to it is un-maximized in place
and moved with the edge, then re-maximized when the mouse is released.
