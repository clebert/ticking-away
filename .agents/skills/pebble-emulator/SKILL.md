---
name: pebble-emulator
description: >-
  Build the Pebble (gabbro) watchface, run it in the QEMU emulator, screenshot it, and open the
  image so the user can see the current implementation. Use when asked to run, test, preview, or
  screenshot the Pebble / gabbro / watchface target on the simulator or emulator.
---

# Run the Pebble watchface in the emulator

Goal: get from a code change to an on-screen screenshot the user can see — fast, and reliably enough
that a flaky emulator never blocks you. The Pebble target is the thin C shell in
[bin/pebble](../../../bin/pebble) linking the Zig render core; `gabbro` is the Pebble Round 2
(260×260).

## Locate the toolchain

The one-time SDK install is documented in the **Pebble Watchface** section of
[README.md](../../../README.md) (`uv tool install pebble-tool --python 3.13` then
`pebble sdk install latest`). Assume it is installed. Locate `pebble` if it is not on `PATH`; Zig
must be available on `PATH`:

```bash
# pebble CLI (rebble pebble-tool), installed via uv
PEBBLE="$(command -v pebble || echo "$HOME/.local/bin/pebble")"
"$PEBBLE" --version            # e.g. "Pebble Tool v5.0.36 (active SDK: v4.9.169)"

zig version                    # expect 0.16.0
```

If `pebble` is missing entirely, stop and point the user at the README install block rather than
guessing install commands. If `zig` is missing or the version is not `0.16.0`, stop and ask the user
to make the project Zig available on `PATH`.

## Build → run → show (the loop)

Run from the repo root. After any code change, repeat all of it. The emulator stays up between runs
(`pgrep -fl qemu-pebble`), so once it has booted, a reinstall is fast — there is no QEMU reboot to
wait on.

```bash
zig build pebble-lib                                        # cross-compile bin/pebble/libwatchface.a
( cd bin/pebble && "$PEBBLE" clean && "$PEBBLE" build )     # clean before build; links the .pbw
( cd bin/pebble && "$PEBBLE" install --emulator gabbro )    # boots QEMU if needed
```

**Always `pebble clean` before `pebble build`.** `zig build pebble-lib` restores
`bin/pebble/libwatchface.a` from its content-addressed cache with the archive's _original_ mtime, so
after the first build waf's timestamp check sees an "unchanged" library and relinks in ~0.02s
**without picking up the code change** — shipping a stale `.pbw` that silently ignores every edit
since the first build. `pebble clean` (a ~1.4s full relink) forces waf to rebuild from the current
library. The tell for a skipped relink is a sub-0.1s `pebble build`; a real relink prints
`Creating app_bundle`.

Then capture — but **poll until the face has painted**, because a screenshot taken during boot grabs
the loading frame: a flat light-grey disc (~21% near-black — only the corners outside the round
display). A rendered face is mostly black (≥90% near-black: the black disc with the prism drawn on
it), so a >50% near-black fraction is a reliable, config-independent ready signal. Run this as a
**background** Bash command — foreground `sleep` is blocked, so the poll must run detached; you are
notified when it finishes:

```bash
for i in $(seq 1 20); do
  "$PEBBLE" screenshot --no-open /tmp/pebble.png >/dev/null 2>&1
  ready=$(python3 -W ignore -c "
from PIL import Image
px = list(Image.open('/tmp/pebble.png').convert('RGB').getdata())
nb = sum(1 for (r, g, b) in px if max(r, g, b) < 30)
print(1 if nb > len(px) * 0.5 else 0)
")
  [ "$ready" = 1 ] && break
  sleep 1
done
open /tmp/pebble.png                                        # macOS: actually show it to the user
```

Then reference the image to the user, e.g. [/tmp/pebble.png](/tmp/pebble.png). **Always look at the
capture** (read the PNG): a correct frame is the prism on a black disc. A flat grey disc with a
small white centre dot is the not-yet-painted boot frame (the poll should prevent it); the Pebble
logo or a progress bar means the firmware is still booting or stuck — see recovery below.

## Install can fail silently — read the output, not the exit code

`pebble install` **exits 0 even when it prints `App install failed`**, so never trust the exit code
or a chained `&&`; grep its output for `App install succeeded`. Two distinct failure modes, with
different fixes:

- **Cold-boot timeout (transient).** A fresh QEMU takes longer to boot than pebble-tool's ~4s
  firmware wait, so the first `install` after a boot may report a timeout or "not ready". Just
  re-run `install` — it connects to the now-booted QEMU and succeeds.
- **Boot loop (corrupted emulator state).** If installs keep failing, or the emulator window shows
  the Pebble logo with a progress bar that keeps resetting and never reaches the watchface, the
  persistent flash (`qemu_spi_flash.bin`) is corrupted — usually from earlier failed installs piling
  up. Recover with `pebble wipe`, then a fresh install:

  ```bash
  "$PEBBLE" kill            # stop the looping QEMU process
  "$PEBBLE" wipe            # clear persistent storage (installed apps, settings) — this clears the loop
  ( cd bin/pebble && "$PEBBLE" install --emulator gabbro )   # fresh boot; expect "App install succeeded."
  ```

  `pebble kill` **alone does not fix a boot loop** — it only stops the process, and the next launch
  reloads the same corrupted flash. `pebble wipe` is what clears it. (`pebble wipe --everything`
  also removes account data and logs you out; rarely needed.) The
  [Pebble FAQ](https://developer.repebble.com/faqs/) prescribes `pebble wipe` for an emulator that
  is "stuck, crashing, or behaving oddly". After a clean wipe, reinstalling into the still-running
  emulator works again — the fast reuse path itself is sound; only stale state breaks it.

## Gotchas

- **The face shows the real time and repaints once per minute.** It reads the live clock and only
  redraws on a `MINUTE_UNIT` tick ([bin/pebble/main.c](../../../bin/pebble/main.c)); the render
  depends only on the integer hour/minute, so it never updates more often on its own. The capture
  therefore shows the current time (to within a minute). Don't try to pin a fixed time with
  `emu-set-time` — it does not reliably repaint the face. When comparing two builds, capture both
  within the same wall-clock minute; the rainbow beam is the hour hand and advances each minute, so
  a time difference between shots reads as a rendering difference.
- **Opaque panel.** Every pixel is packed opaque in
  [bin/pebble/render.zig](../../../bin/pebble/render.zig), so alpha/transparency never show on
  device; untouched area reads as black.
