#!/bin/bash
zenity --question \
  --title="Delete Current Wallpaper?" \
  --text="Are you sure you want to delete current wallpaper?" \
  --ok-label="Delete" \
  --cancel-label="Cancel"

if [ $? -eq 0 ]; then
  # User clicked Okay — run your script here
  /home/broot/bin/wallpaper.sh delete
fi