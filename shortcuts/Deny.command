#!/usr/bin/env bash
/Applications/Loggdin.app/Contents/MacOS/loggdin deny
osascript -e 'display notification "Denied permission request" with title "loggdin Denied" sound name "Purr"'
