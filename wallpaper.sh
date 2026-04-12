#!/usr/bin/env bash
# =============================================================================
# wallpaper.sh — Rotating desktop wallpaper manager
# =============================================================================
# Usage:
#   wallpaper.sh next           Advance to next wallpaper in shuffled list
#   wallpaper.sh prev           Go to previous wallpaper
#   wallpaper.sh fav            Mark current wallpaper as a favorite
#   wallpaper.sh unfav          Remove current wallpaper from favorites
#   wallpaper.sh favmode on     Switch to favorites-only rotation
#   wallpaper.sh favmode off    Return to main (full) rotation
#   wallpaper.sh status         Show current wallpaper and mode
#   wallpaper.sh rebuild        Reshuffle and rebuild the image list
#   wallpaper.sh list           Print the current shuffled list
#   wallpaper.sh listfavs       Print current favorites list
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# CONFIGURATION — edit these to match your environment
# -----------------------------------------------------------------------------

# Root folder containing wallpaper images (searched recursively)
IMAGE_ROOT="${WALLPAPER_ROOT:-$HOME/wallpapers}"

# File extensions to include (case-insensitive)
EXTENSIONS=("jpg" "jpeg" "png" "webp" "bmp" "tiff")

# State directory (stores shuffled list, pointer, favorites, mode flag)
STATE_DIR="${WALLPAPER_STATE:-$HOME/.config/wallpaper}"

# ImageMagick: set to "true" to composite filename onto the wallpaper
USE_IMAGEMAGICK="${WALLPAPER_OVERLAY:-true}"

# Temporary file used as the actual set wallpaper (overlay composite)
OVERLAY_FILE="/tmp/wallpaper_current.jpg"

# OS command to set the desktop wallpaper.
# Use %FILE% as the placeholder for the image path.
# Examples:
#   feh:         feh --bg-max %FILE%
#   swaybg:      swaybg -i %FILE% -m fill &
#   xfconf:      xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor0/image-path -s %FILE%
#   macOS:       osascript -e 'tell application "Finder" to set desktop picture to POSIX file "%FILE%"'
SET_WALLPAPER_CMD="feh --bg-max %FILE%"

# ImageMagick overlay options
OVERLAY_FONT="DejaVu-Sans-Bold"
OVERLAY_FONTSIZE=20    # Character height scale: pointsize = image_width * OVERLAY_FONTSIZE / 1000
OVERLAY_COLOR="white"
OVERLAY_SHADOW_COLOR="black"
OVERLAY_OPACITY=0.50          # Text opacity (0.0–1.0)
OVERLAY_MARGIN=20

# -----------------------------------------------------------------------------
# STATE FILES
# -----------------------------------------------------------------------------

LIST_FILE="$STATE_DIR/list.txt"          # Shuffled list of all images
POINTER_FILE="$STATE_DIR/pointer.txt"    # Current index into list
FAVS_FILE="$STATE_DIR/favorites.txt"     # One path per line
CURRENT_FILE="$STATE_DIR/current.txt"    # Absolute path of current wallpaper
MODE_FILE="$STATE_DIR/mode.txt"          # "main" or "favs"
FAVS_LIST_FILE="$STATE_DIR/favs_list.txt" # Shuffled favorites list
FAVS_POINTER_FILE="$STATE_DIR/favs_pointer.txt"

# -----------------------------------------------------------------------------
# HELPERS
# -----------------------------------------------------------------------------

die()      { echo "ERROR: $*" >&2; exit 1; }
info()     { echo "[wallpaper] $*"; }
warn()     { echo "[wallpaper] WARNING: $*" >&2; }
notify()   { command -v zenity &>/dev/null && zenity --notification --text="$*" 2>/dev/null || true; }

require_cmd() {
    command -v "$1" &>/dev/null || die "'$1' is required but not found in PATH."
}

init_state_dir() {
    mkdir -p "$STATE_DIR"
    touch "$FAVS_FILE"
    [[ -f "$MODE_FILE" ]] || echo "main" > "$MODE_FILE"
}

get_mode() {
    cat "$MODE_FILE" 2>/dev/null || echo "main"
}

get_current() {
    cat "$CURRENT_FILE" 2>/dev/null || echo "(none)"
}

# Build a regex alternation from extension list for find
ext_pattern() {
    local IFS='|'
    echo "${EXTENSIONS[*]}"
}

build_find_args() {
    # Emit: -iname "*.jpg" -o -iname "*.png" … wrapped in parens
    local first=true
    echo "("
    for ext in "${EXTENSIONS[@]}"; do
        if $first; then
            echo "-iname" "\"*.$ext\""
            first=false
        else
            echo "-o" "-iname" "\"*.$ext\""
        fi
    done
    echo ")"
}

# Rebuild (or build) the main shuffled list
rebuild_main_list() {
    info "Scanning $IMAGE_ROOT for images..."
    [[ -d "$IMAGE_ROOT" ]] || die "IMAGE_ROOT '$IMAGE_ROOT' does not exist."

    local find_cmd="find \"$IMAGE_ROOT\" -type f \("
    local first=true
    for ext in "${EXTENSIONS[@]}"; do
        if $first; then
            find_cmd+=" -iname \"*.$ext\""
            first=false
        else
            find_cmd+=" -o -iname \"*.$ext\""
        fi
    done
    find_cmd+=" \)"

    eval "$find_cmd" | shuf > "$LIST_FILE"
    local count
    count=$(wc -l < "$LIST_FILE")
    echo "0" > "$POINTER_FILE"
    info "Found and shuffled $count images."
}

# Rebuild the shuffled favorites list from FAVS_FILE
rebuild_favs_list() {
    if [[ ! -s "$FAVS_FILE" ]]; then
        warn "Favorites list is empty."
        > "$FAVS_LIST_FILE"
        echo "0" > "$FAVS_POINTER_FILE"
        return
    fi
    shuf "$FAVS_FILE" > "$FAVS_LIST_FILE"
    echo "0" > "$FAVS_POINTER_FILE"
    local count
    count=$(wc -l < "$FAVS_LIST_FILE")
    info "Shuffled $count favorites."
}

# Get the nth line from a file (1-indexed)
get_line() {
    local file="$1" n="$2"
    sed -n "${n}p" "$file"
}

# Apply ImageMagick filename overlay and write to OVERLAY_FILE
apply_overlay() {
    local src="$1"
    local label dir parent

    # Include parent dir in label unless image sits directly in IMAGE_ROOT
    dir=$(dirname "$src")
    if [[ "$(realpath "$dir" 2>/dev/null || echo "$dir")" == "$(realpath "$IMAGE_ROOT" 2>/dev/null || echo "$IMAGE_ROOT")" ]]; then
        label=$(basename "$src")
    else
        parent=$(basename "$dir")
        label="$parent/$(basename "$src")"
    fi

    if ! command -v convert &>/dev/null; then
        warn "ImageMagick 'convert' not found — skipping overlay. Set USE_IMAGEMAGICK=false to suppress this warning."
        cp "$src" "$OVERLAY_FILE"
        return
    fi

    # Pointsize (character height) scales with image width for consistent appearance across resolutions
    local width fontsize gravity
    width=$(identify -format "%w" "$src" 2>/dev/null) || width=1920
    fontsize=$(( width * OVERLAY_FONTSIZE / 1000 ))
    [[ $fontsize -lt 10 ]] && fontsize=10

    # Pick a random corner each time
    local corners=("NorthWest" "NorthEast" "SouthWest" "SouthEast")
    gravity="${corners[$((RANDOM % 4))]}"

    # Draw text on a transparent layer then composite at OVERLAY_OPACITY
    convert "$src" \
        \( -clone 0 -alpha transparent \
           -font "$OVERLAY_FONT" -pointsize "$fontsize" -gravity "$gravity" \
           -fill "$OVERLAY_SHADOW_COLOR" \
           -annotate "+$((OVERLAY_MARGIN+2))+$((OVERLAY_MARGIN-2))" "$label" \
           -fill "$OVERLAY_COLOR" \
           -annotate "+${OVERLAY_MARGIN}+${OVERLAY_MARGIN}" "$label" \
           -channel Alpha -evaluate multiply "$OVERLAY_OPACITY" \) \
        -composite \
        "$OVERLAY_FILE" 2>/dev/null \
    || { warn "ImageMagick overlay failed — using original file."; cp "$src" "$OVERLAY_FILE"; }
}

# Run the OS-specific set-wallpaper command
set_wallpaper_os() {
    local file="$1"
    local cmd="${SET_WALLPAPER_CMD//%FILE%/$file}"
    eval "$cmd" || warn "Set-wallpaper command failed: $cmd"
}

# Resolve active list/pointer files based on current mode, building if needed
resolve_list() {
    local mode
    mode=$(get_mode)

    if [[ "$mode" == "favs" ]]; then
        LIST_ACTIVE="$FAVS_LIST_FILE"
        POINTER_ACTIVE="$FAVS_POINTER_FILE"
        if [[ ! -s "$LIST_ACTIVE" ]]; then
            warn "Favorites list is empty or missing. Rebuilding..."
            rebuild_favs_list
            [[ -s "$LIST_ACTIVE" ]] || die "No favorites to display. Add some with: wallpaper.sh fav"
        fi
    else
        LIST_ACTIVE="$LIST_FILE"
        POINTER_ACTIVE="$POINTER_FILE"
        if [[ ! -s "$LIST_ACTIVE" ]]; then
            info "No image list found. Building one now..."
            rebuild_main_list
        fi
    fi
}

# Display the image at a given 0-based index and update state
display_at_index() {
    local list_file="$1" pointer_file="$2" show_idx="$3" next_ptr="$4"
    local mode total image display_file
    mode=$(get_mode)
    total=$(wc -l < "$list_file")

    image=$(get_line "$list_file" $(( show_idx + 1 )))
    echo "$next_ptr" > "$pointer_file"

    [[ -f "$image" ]] || { warn "File not found: $image — skipping."; return 1; }

    echo "$image" > "$CURRENT_FILE"
    info "Setting: $image  ($(( show_idx + 1 ))/$total, mode=$mode)"

    display_file="$image"
    if [[ "$USE_IMAGEMAGICK" == "true" ]]; then
        apply_overlay "$image"
        display_file="$OVERLAY_FILE"
    fi

    set_wallpaper_os "$display_file"
}

favmode_on() {
    echo "favs" > "$MODE_FILE"
    info "Switched to favorites-only mode."
    notify "Wallpaper: favorites mode"
    do_redisplay
}

favmode_off() {
    echo "main" > "$MODE_FILE"
    info "Switched to main rotation mode."
    notify "Wallpaper: main rotation mode"
    do_redisplay
}

# Redisplay the last shown image without moving the pointer
do_redisplay() {
    resolve_list
    local total idx show_idx
    total=$(wc -l < "$LIST_ACTIVE")
    [[ $total -gt 0 ]] || die "Image list is empty."

    idx=$(cat "$POINTER_ACTIVE" 2>/dev/null || echo "0")
    show_idx=$(( (idx - 1 + total) % total ))
    display_at_index "$LIST_ACTIVE" "$POINTER_ACTIVE" "$show_idx" "$idx"
}

# Core: advance to next image in whichever list is active
do_next() {
    resolve_list
    local total idx show_idx
    total=$(wc -l < "$LIST_ACTIVE")
    [[ $total -gt 0 ]] || die "Image list is empty."

    idx=$(cat "$POINTER_ACTIVE" 2>/dev/null || echo "0")
    show_idx=$(( idx % total ))
    # Pointer after display points to the one after what we just showed
    display_at_index "$LIST_ACTIVE" "$POINTER_ACTIVE" "$show_idx" $(( (show_idx + 1) % total ))
}

# Core: step back to previous image in whichever list is active
do_prev() {
    resolve_list
    local total idx show_idx
    total=$(wc -l < "$LIST_ACTIVE")
    [[ $total -gt 0 ]] || die "Image list is empty."

    idx=$(cat "$POINTER_ACTIVE" 2>/dev/null || echo "0")
    # Pointer points to the image after what was last shown (i.e. current+1).
    # Step back 2 to land on the one before current; wrap with modulo.
    show_idx=$(( (idx - 2 + total) % total ))
    # After display, pointer should point to current (show_idx+1), ready for next.
    display_at_index "$LIST_ACTIVE" "$POINTER_ACTIVE" "$show_idx" $(( (show_idx + 1) % total ))
}

# -----------------------------------------------------------------------------
# COMMAND DISPATCH
# -----------------------------------------------------------------------------

CMD="${1:-help}"

init_state_dir

case "$CMD" in

    next)
        do_next
        ;;

    prev)
        do_prev
        ;;

    fav)
        current=$(get_current)
        [[ "$current" != "(none)" ]] || die "No current wallpaper is set yet. Run 'next' first."
        if grep -qxF "$current" "$FAVS_FILE" 2>/dev/null; then
            info "Already a favorite: $current"
        else
            echo "$current" >> "$FAVS_FILE"
            [[ -f "$FAVS_LIST_FILE" ]] && echo "$current" >> "$FAVS_LIST_FILE"
            info "Added to favorites: $current"
            notify "Favorited: $(basename "$current")"
        fi
        ;;

    unfav)
        current=$(get_current)
        [[ "$current" != "(none)" ]] || die "No current wallpaper is set yet."
        if grep -qxF "$current" "$FAVS_FILE" 2>/dev/null; then
            grep -vxF "$current" "$FAVS_FILE" > "$FAVS_FILE.tmp" && mv "$FAVS_FILE.tmp" "$FAVS_FILE"
            grep -vxF "$current" "$FAVS_LIST_FILE" > "$FAVS_LIST_FILE.tmp" && mv "$FAVS_LIST_FILE.tmp" "$FAVS_LIST_FILE" 2>/dev/null || true
            info "Removed from favorites: $current"
            notify "Unfavorited: $(basename "$current")"
            [[ "$(get_mode)" == "favs" ]] && do_next
        else
            info "Not in favorites: $current"
        fi
        ;;

    favmode)
        SUBARG="${2:-}"
        case "$SUBARG" in
            on)   favmode_on ;;
            off)  favmode_off ;;
            "")   [[ "$(get_mode)" == "favs" ]] && favmode_off || favmode_on ;;
            *)    die "Usage: wallpaper.sh favmode [on|off]" ;;
        esac
        ;;

    status)
        mode=$(get_mode)
        current=$(get_current)
        echo "Mode:    $mode"
        echo "Current: $current"

        if [[ -f "$LIST_FILE" ]]; then
            total=$(wc -l < "$LIST_FILE")
            idx=$(cat "$POINTER_FILE" 2>/dev/null || echo "0")
            echo "Main list: $total images, pointer at $idx"
        else
            echo "Main list: not built yet (run: wallpaper.sh rebuild)"
        fi

        if [[ -f "$FAVS_FILE" ]]; then
            favcount=$(wc -l < "$FAVS_FILE")
            echo "Favorites: $favcount"
        fi

        if [[ "$mode" == "favs" && -f "$FAVS_LIST_FILE" ]]; then
            ftotal=$(wc -l < "$FAVS_LIST_FILE")
            fidx=$(cat "$FAVS_POINTER_FILE" 2>/dev/null || echo "0")
            echo "Favs list: $ftotal shuffled, pointer at $fidx"
        fi
        ;;

    delete)
        current=$(get_current)
        [[ "$current" != "(none)" ]] || die "No current wallpaper is set yet."
        [[ -f "$current" ]] || die "File not found: $current"
        rm "$current"
        info "Deleted: $current"
        # Remove from list and favorites if present
        grep -vxF "$current" "$LIST_FILE" > "$LIST_FILE.tmp" && mv "$LIST_FILE.tmp" "$LIST_FILE" 2>/dev/null || true
        grep -vxF "$current" "$FAVS_FILE" > "$FAVS_FILE.tmp" && mv "$FAVS_FILE.tmp" "$FAVS_FILE" 2>/dev/null || true
        do_next
        ;;

    rebuild)
        [[ "$(get_mode)" == "favs" ]] && rebuild_favs_list || rebuild_main_list
        do_next
        ;;

    list)
        [[ -f "$LIST_FILE" ]] || die "No list built yet. Run: wallpaper.sh rebuild"
        cat -n "$LIST_FILE"
        ;;

    listfavs)
        [[ -s "$FAVS_FILE" ]] || { info "No favorites yet."; exit 0; }
        cat -n "$FAVS_FILE"
        ;;

    help|--help|-h)
        mode=$(get_mode)
        current=$(get_current)
        echo "Current: $current"
        echo "Mode:    $( [[ "$mode" == "favs" ]] && echo "favorites" || echo "full rotation" )"
        echo ""
        echo "Usage:"
        echo "  wallpaper.sh next              Advance to next wallpaper"
        echo "  wallpaper.sh prev              Go to previous wallpaper"
        echo "  wallpaper.sh fav               Mark current as favorite"
        echo "  wallpaper.sh unfav             Remove current from favorites"
        echo "  wallpaper.sh favmode on|off    Switch to/from favorites-only rotation"
        echo "  wallpaper.sh delete            Delete current wallpaper file and advance to next"
        echo "  wallpaper.sh rebuild           Reshuffle and rebuild the image list"
        echo "  wallpaper.sh status            Show full status"
        ;;

    *)
        echo "[wallpaper] Unknown command: '$CMD'" >&2
        echo "            Run 'wallpaper.sh help' for usage." >&2
        exit 1
        ;;
esac
