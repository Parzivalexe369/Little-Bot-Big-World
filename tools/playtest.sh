#!/usr/bin/env bash
# Dev helper: runs the end-to-end playtest (windowed). Extra args are passed to the runner.
cd "$(dirname "$0")/.."
timeout 900 ./tools/Godot_v4.7.2-stable_win64_console.exe --path . res://tools/playtest_runner.tscn -- "$@" > /tmp/lbbw_playtest.txt 2>&1
echo "exit: $?"
grep -E "PLAYTEST|SCRIPT ERROR|ERROR:|WARNING:" /tmp/lbbw_playtest.txt | grep -vE "ui_theme|BUG: Unreferenced|Leaked instance|Pages in use|RID allocations|resources still in use|never freed" | head -${LINES_MAX:-120}
