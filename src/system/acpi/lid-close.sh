#!/bin/bash
# Skip s2idle when battery is low — Modern Standby drains fast on this hardware.
THRESHOLD=30
BAT_CAP=$(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -1)

if [[ -n "$BAT_CAP" && "$BAT_CAP" -le "$THRESHOLD" ]]; then
    /usr/bin/systemctl hibernate
else
    /usr/bin/systemctl suspend-then-hibernate
fi
