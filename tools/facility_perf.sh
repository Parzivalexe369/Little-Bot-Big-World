#!/usr/bin/env bash
# Dev helper: GPU/CPU frame time at a spot in each sci-fi area (windowed, 1600x900).
# Usage: tools/facility_perf.sh [quality=N] [profile]
cd "$(dirname "$0")/.."
for spot in "lab 0,0.1,24 180" "lab_optics -6,0.1,-4 200" "reactor 300,4.1,-18 180" "reactor_entry 300,0.1,30 180" "quantum 605,10.1,-22 180" "quantum_well 600,0.1,16 180" "quantum_final 634,13.6,-50 180"; do
	set -- $spot
	label=$1; at=$2; yaw=$3
	shift 3
	out=$(timeout 120 ./tools/Godot_v4.7.2-stable_win64_console.exe --path . res://tools/perf_runner.tscn -- scene=res://scenes/facility/facility.tscn at=$at 0 0 $yaw "${@}" $EXTRA 2>&1 | grep -E "^PERF|^RENDER|SCRIPT ERROR|SHADER ERROR" | head -4)
	echo "[$label] $out"
done
