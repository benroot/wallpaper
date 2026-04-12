#!/bin/bash
zenity --question \
  --title="Remove from Favorites?" \
  --text="Are you sure you want to remove the current wallpaper from favorites?" \
  --ok-label="Unfav" \
  --cancel-label="Cancel"

if [ $? -eq 0 ]; then
  # User clicked Okay — run your script here
  /home/broot/bin/wallpaper.sh unfav
fi
