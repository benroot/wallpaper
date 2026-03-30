# wallpaper.sh

A bash-based wallpaper rotation manager for a home media server or desktop Linux
environment. Shuffles a folder (or hierarchy of folders) of images, cycles through
them on a cron timer, optionally composites the filename onto the image using
ImageMagick, and supports a favorites system with a dedicated rotation mode.

---

## Requirements

| Dependency | Required | Purpose |
|---|---|---|
| `bash` ≥ 4.0 | Yes | Script runtime |
| `find`, `shuf`, `wc`, `grep`, `sed` | Yes | Core utilities (standard on Linux) |
| `imagemagick` (`convert`) | Optional | Filename overlay on wallpaper |
| A wallpaper-setter command | Yes | Actually applies the wallpaper to the desktop |

### Wallpaper setter options by environment

| Environment | Command (set in `SET_WALLPAPER_CMD`) |
|---|---|
| X11 with `feh` | `feh --bg-scale %FILE%` |
| Sway / Wayland | `swaybg -i %FILE% -m fill` |
| XFCE | `xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor0/image-path -s %FILE%` |
| GNOME | `gsettings set org.gnome.desktop.background picture-uri "file://%FILE%"` |
| macOS | `osascript -e 'tell application "Finder" to set desktop picture to POSIX file "%FILE%"'` |

---

## Installation

```bash
# 1. Clone or copy wallpaper.sh to a location on your PATH
cp wallpaper.sh ~/bin/wallpaper
chmod +x ~/bin/wallpaper

# 2. Edit the configuration section at the top of the script:
#    - IMAGE_ROOT     → where your wallpapers live
#    - SET_WALLPAPER_CMD → your desktop environment's setter command
#    - USE_IMAGEMAGICK  → true/false for filename overlay

# 3. Build the initial shuffled list
wallpaper next      # builds list automatically on first run
# or explicitly:
wallpaper rebuild
```

---

## Configuration

All configuration lives at the top of the script. You can also override via
environment variables before calling the script.

| Variable | Default | Description |
|---|---|---|
| `WALLPAPER_ROOT` | `~/wallpapers` | Root folder scanned recursively for images |
| `WALLPAPER_STATE` | `~/.config/wallpaper` | Directory where state files are stored |
| `WALLPAPER_OVERLAY` | `true` | Whether to use ImageMagick to add filename overlay |
| `SET_WALLPAPER_CMD` | `feh --bg-scale %FILE%` | OS command; `%FILE%` is replaced with image path |

---

## State Files

The script stores all state in `~/.config/wallpaper/` (or `$WALLPAPER_STATE`):

| File | Contents |
|---|---|
| `list.txt` | Shuffled list of all images (one path per line) |
| `pointer.txt` | Current position in `list.txt` (0-based integer) |
| `current.txt` | Absolute path of the currently displayed wallpaper |
| `favorites.txt` | User-curated list of favorite image paths |
| `favs_list.txt` | Shuffled copy of favorites (rebuilt on `favmode on`) |
| `favs_pointer.txt` | Current position in `favs_list.txt` |
| `mode.txt` | Active rotation mode: `main` or `favs` |

The overlay composite is always written to `/tmp/wallpaper_current.jpg` so
the originals are never modified.

---

## Usage

```
wallpaper next           Advance to the next wallpaper (designed for cron)
wallpaper prev           [NOT IMPLEMENTED] Go back one image
wallpaper fav            Mark the current wallpaper as a favorite
wallpaper unfav          Remove the current wallpaper from favorites
wallpaper favmode on     Switch to favorites-only rotation
wallpaper favmode off    Return to main (full) rotation
wallpaper status         Show current image, mode, and list stats
wallpaper rebuild        Rescan IMAGE_ROOT and rebuild shuffled list
wallpaper list           Print the current shuffled list with line numbers
wallpaper listfavs       Print the current favorites list
wallpaper help           Show usage summary
```

---

## Cron Setup

The `next` command is designed to be driven by cron. Example: change wallpaper
every 30 minutes.

```cron
*/30 * * * * /home/youruser/bin/wallpaper next >> /var/log/wallpaper.log 2>&1
```

If your wallpaper setter needs a display environment variable (common on X11):

```cron
*/30 * * * * DISPLAY=:0 XAUTHORITY=/home/youruser/.Xauthority /home/youruser/bin/wallpaper next
```

---

## ImageMagick Overlay

When `USE_IMAGEMAGICK=true`, the script uses `convert` to render the image's
filename in the corner of the wallpaper before setting it. The original file
is never modified — the composite is written to a temp file.

Overlay appearance is configured in the script:

```bash
OVERLAY_FONT="DejaVu-Sans-Bold"
OVERLAY_FONTSIZE=28
OVERLAY_COLOR="white"
OVERLAY_SHADOW_COLOR="black"
OVERLAY_GRAVITY="SouthEast"   # NorthWest | NorthEast | SouthWest | SouthEast
OVERLAY_MARGIN=20
```

To list available fonts on your system:

```bash
convert -list font | grep Font:
```

---

## Favorites Workflow

```bash
# While browsing wallpapers normally, mark a keeper:
wallpaper fav

# Later, switch into favorites-only mode:
wallpaper favmode on

# The favorites list is reshuffled and cycles independently.
# Return to the full rotation at any time:
wallpaper favmode off

# Review your favorites:
wallpaper listfavs

# Remove the currently displayed image from favorites:
wallpaper unfav
```

Favorites are stored as plain text paths in `favorites.txt` and can be
edited directly in any text editor.

---

## Not Yet Implemented

- `prev` — step backward one image in the current list
- Per-image display-duration weighting (show favorites more often in main mode)
- Web UI / status page
- Automatic removal of dead paths from `list.txt` and `favorites.txt` on rebuild

---

## Tips

- **Image root layout**: The script uses `find -type f` recursively, so any
  folder structure works — flat, nested by theme, by date, etc.
- **Re-shuffling**: Run `wallpaper rebuild` after adding or removing images.
  The pointer resets to 0 and the list is reshuffled.
- **Favorites reshuffle**: The favorites list is reshuffled each time you run
  `favmode on`. Run it again to reshuffle without changing mode.
- **Manual override**: Set `current.txt` to any path by hand, then run
  `wallpaper fav` to add it — useful for scripted seeding of favorites.
