#!/bin/bash

# If no arguments provided, show usage
if [[ $# -eq 0 ]]; then
    echo "Usage: $0 <zone_file1> [zone_file2] ..."
    echo "Example: $0 /etc/coredns/Zones/net/example.zone"
    exit 1
fi

# Process each zone file passed as argument
for zone in "$@"; do
    if [[ ! -f "$zone" ]]; then
        echo "❌ Zone file not found: $zone"
        continue
    fi

    echo "[*] Processing $zone"

    # Extract current serial
    current_serial=$(awk '$4 == "SOA" { print $7 }' "$zone")
    today=$(date +%Y%m%d)

    if [[ -z "$current_serial" ]]; then
        echo "❌ Could not find serial in $zone"
        continue
    fi

    current_day=${current_serial:0:8}
    current_count=${current_serial:8:2}

    if [[ "$current_day" == "$today" ]]; then
        new_count=$(printf "%02d" $((10#$current_count + 1)))
    else
        new_count="01"
    fi

    new_serial="${today}${new_count}"

    echo "→ Updating serial from $current_serial to $new_serial"

    # Replace serial in the file
    sed -i "s/$current_serial/$new_serial/" "$zone"
done