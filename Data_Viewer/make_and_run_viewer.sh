#!/usr/bin/env bash

BROWSER="${1:-firefox}"
FOLDER="${2:-../Force_Sensor_Data}"

python3 make_viewer.py "$FOLDER"

"$BROWSER" "$FOLDER/viewer.html"
