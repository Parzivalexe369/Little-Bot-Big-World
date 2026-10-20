#!/usr/bin/env bash
# Dev helper: automated playthrough of the three sci-fi areas (windowed). Extra args go to the runner.
cd "$(dirname "$0")/.."
timeout 900 ./tools/Godot_v4.7.2-stable_win64_console.exe --path . res://tools/facility_playtest_runner.tscn -- "$@" > /tmp/lbbw_facility.txt 2>&1
echo "exit: $?"
grep -E "FACILITY|SCRIPT ERROR|ERROR:" /tmp/lbbw_facility.txt | grep -vE "ui_theme|BUG: Unreferenced|Leaked instance|Pages in use|RID allocations|resources still in use|never freed|RIDs of type" | head -${LINES_MAX:-200}
