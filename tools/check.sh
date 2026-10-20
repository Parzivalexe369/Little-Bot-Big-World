#!/usr/bin/env bash
# Dev helper: refresh Godot's import/class cache, then compile-check every script.
cd "$(dirname "$0")/.."
GODOT=./tools/Godot_v4.7.2-stable_win64_console.exe
timeout 300 $GODOT --headless --path . --import > /tmp/lbbw_import.txt 2>&1
grep -E "SCRIPT ERROR|Parse Error" -A1 /tmp/lbbw_import.txt | head -20
timeout 120 $GODOT --headless --path . --script res://tools/check_scripts.gd > /tmp/lbbw_check.txt 2>&1
grep -E "checked|FAILED|Parse Error|Compile Error" -A1 /tmp/lbbw_check.txt | head -60
