#!/usr/bin/env bash
/Applications/Loggdin.app/Contents/MacOS/loggdin allow 10m
osascript -e 'display notification "Approved action for 10 minutes" with title "loggdin Approved" sound name "Glass"'
