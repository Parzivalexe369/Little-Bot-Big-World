#!/usr/bin/env bash
# Dev helper: windowed screenshot capture. Usage: tools/capture.sh shots.json [scene]
cd "$(dirname "$0")/.."
timeout 240 ./tools/Godot_v4.7.2-stable_win64_console.exe --path . res://tools/capture_runner.tscn -- "$@" > /tmp/lbbw_capture.txt 2>&1
grep -vE "^\s*$|ui_theme|GDScript backtrace|^\s+\[[0-9]+\]" /tmp/lbbw_capture.txt | grep -E "saved|ERROR|SCRIPT|WARNING|capture done|built" -A1 | head -${LINES_MAX:-40}
