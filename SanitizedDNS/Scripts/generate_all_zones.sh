#!/bin/bash
set -euo pipefail

ROOT_DIR="/etc/coredns"
ZONES_DIR="${ROOT_DIR}/Zones"
KEY_DIR="${ROOT_DIR}/Keys"
ARCHIVE_DIR="${KEY_DIR}/Archive"
CACHE_DIR="${ROOT_DIR}/Cache"
SCRIPT_DIR="${ROOT_DIR}/Scripts"
OUT_DIR="${ROOT_DIR}/AutoZoneGen"

ALGORITHM="ECDSAP256SHA256"
UPDATE_SOA_SCRIPT="${SCRIPT_DIR}/update_soa_serials.sh"

# Parse arguments
CLEAR_MODE=false
for arg in "$@"; do
    case $arg in
        --clear)
            CLEAR_MODE=true
            shift
            ;;
        *)
            echo "Unknown argument: $arg"
            echo "Usage: $0 [--clear]"
            echo "  --clear    Clear AutoZoneGen & Keys directories (excluding Archive)"
            exit 1
            ;;
    esac
done

mkdir -p "$KEY_DIR" "$OUT_DIR" "$CACHE_DIR" "$ARCHIVE_DIR"
chown -R coredns:coredns "$KEY_DIR" "$OUT_DIR" "$CACHE_DIR"
chmod 750 "$KEY_DIR" "$CACHE_DIR" "$ARCHIVE_DIR"

# Handle clear mode
if [[ "$CLEAR_MODE" == true ]]; then
    echo "[*] Clearing AutoZoneGen and Keys directories (excluding Archive)..."
    
    # Clear AutoZoneGen directory
    if [[ -d "$OUT_DIR" ]]; then
        rm -rf "${OUT_DIR:?}"/*
        echo "[✓] Cleared $OUT_DIR"
    fi
    
    # Clear Keys directory but preserve Archive
    if [[ -d "$KEY_DIR" ]]; then
        # Remove all files in KEY_DIR root
        find "$KEY_DIR" -maxdepth 1 -type f -delete
        
        # Remove all directories except Archive
        for dir in "$KEY_DIR"/*/; do
            if [[ -d "$dir" && "$(basename "$dir")" != "Archive" ]]; then
                echo "    Removing directory: $(basename "$dir")"
                rm -rf "$dir"
            fi
        done
        
        echo "[✓] Cleared $KEY_DIR (preserved Archive)"
    fi
    
    # Clear Cache directory
    if [[ -d "$CACHE_DIR" ]]; then
        rm -rf "${CACHE_DIR:?}"/*
        echo "[✓] Cleared $CACHE_DIR"
    fi
    
    echo "[✅] Clear operation completed."
    exit 0
fi

echo "[*] Scanning zones in $ZONES_DIR"

shopt -s globstar nullglob

# Flag to track if any zones were regenerated
zones_changed=false
files_actually_changed=false
changed_zone_files=()
domains_to_regenerate=()

for zonefile in "$ZONES_DIR"/**/*.zone; do
    filename="$(basename "$zonefile" .zone)"
    parent="$(basename "$(dirname "$zonefile")")"
    domain="${filename}.${parent}"
    outfile="${OUT_DIR}/${domain}.conf"
    cachefile="${CACHE_DIR}/${domain}.hash"
    
    # Calculate current zone file hash - normalize whitespace and line endings, exclude SOA serial
    current_hash=$(cat "$zonefile" | tr -d '\r' | sed 's/[[:space:]]*$//' | grep -v "IN.*SOA" | md5sum | cut -d' ' -f1)
    
    # Check if cache file exists and compare hashes
    regenerate=false
    if [[ -f "$cachefile" ]]; then
        cached_hash=$(cat "$cachefile" | tr -d '\n\r')
        if [[ "$cached_hash" != "$current_hash" ]]; then
            echo "[!] Zone $domain has changed (hash mismatch)"
            echo "    Cached: $cached_hash"
            echo "    Current: $current_hash"
            echo "    File: $zonefile"
            regenerate=true
            files_actually_changed=true
            changed_zone_files+=("$zonefile")
            domains_to_regenerate+=("$domain")
        fi
    else
        echo "[!] No cache found for $domain"
        regenerate=true
        files_actually_changed=true
        changed_zone_files+=("$zonefile")
        domains_to_regenerate+=("$domain")
    fi
    
    # Skip if zone hasn't changed and config exists
    if [[ "$regenerate" == false && -f "$outfile" ]]; then
        echo "🟡 Skipping $domain (no changes)"
        continue
    fi
    
    # Mark for regeneration but don't process yet
    zones_changed=true
done

# Archive all keys for domains that need regeneration
if [[ ${#domains_to_regenerate[@]} -gt 0 ]]; then
    echo "[*] Archiving existing keys for ${#domains_to_regenerate[@]} changed domains..."
    timestamp=$(date +%Y%m%d_%H%M%S)
    
    for domain in "${domains_to_regenerate[@]}"; do
        # Extract the zone filename without extension for regex matching
        zone_basename=$(basename "${changed_zone_files[0]}" .zone)
        
        # Find the corresponding zone file for this domain
        domain_zonefile=""
        for zonefile in "${changed_zone_files[@]}"; do
            zonefile_basename=$(basename "$zonefile" .zone)
            if [[ "$domain" == "${zonefile_basename}.$(basename "$(dirname "$zonefile")")" ]]; then
                domain_zonefile="$zonefile"
                break
            fi
        done
        
        if [[ -z "$domain_zonefile" ]]; then
            echo "[⚠] Could not find zone file for domain $domain"
            continue
        fi
        
        zone_name=$(basename "$domain_zonefile" .zone)
        
        # Archive old DNSSEC keys using proper DNSSEC key naming pattern
        mapfile -t old_keys < <(find "$KEY_DIR" -maxdepth 1 \( -name "K${domain}.+*+*.key" -o -name "K${domain}.+*+*.private" \) -type f)
        
        if [[ ${#old_keys[@]} -gt 0 ]]; then
            archive_subdir="${ARCHIVE_DIR}/${domain}_${timestamp}"
            mkdir -p "$archive_subdir"
            echo "[*] Archiving ${#old_keys[@]} old keys for $domain to $archive_subdir"
            
            for key in "${old_keys[@]}"; do
                echo "    Moving: $(basename "$key")"
                mv "$key" "$archive_subdir/"
            done
            
            chown -R coredns:coredns "$archive_subdir"
            echo "[✓] Keys archived successfully for $domain"
        else
            echo "[ℹ] No existing keys found for $domain to archive"
        fi
    done
fi

# Now process all zones again to generate configs and keys
for zonefile in "$ZONES_DIR"/**/*.zone; do
    filename="$(basename "$zonefile" .zone)"
    parent="$(basename "$(dirname "$zonefile")")"
    domain="${filename}.${parent}"
    outfile="${OUT_DIR}/${domain}.conf"
    cachefile="${CACHE_DIR}/${domain}.hash"
    
    # Skip if this domain doesn't need regeneration
    if [[ ! " ${domains_to_regenerate[*]} " =~ " ${domain} " ]] && [[ -f "$outfile" ]]; then
        continue
    fi
    
    # Remove old config file
    rm -f "$outfile"
    
    echo "[*] Regenerating $domain"

    keybase="K${domain}"
    # Use proper DNSSEC key naming pattern to find existing keys
    mapfile -t existing_key_files < <(find "$KEY_DIR" -maxdepth 1 -name "K${domain}.+*+*.key" -type f)
    privfile=""
    keyfile=""

    if [[ ${#existing_key_files[@]} -eq 0 ]]; then
        echo "[*] Generating DNSSEC keys for $domain ..."
        cd "$KEY_DIR"
        base=$(ldns-keygen -a "$ALGORITHM" "$domain" | xargs basename)
        echo "[✓] Generated: $base"
        chown coredns:coredns "${base}.key" "${base}.private"
        chmod 640 "${base}.key" "${base}.private"
        keyfile="${KEY_DIR}/${base}.key"
        privfile="${KEY_DIR}/${base}.private"
    else
        keyfile="${existing_key_files[0]}"
        privfile="${keyfile%.key}.private"
        echo "[✓] Found existing keys for $domain"
    fi

    echo "[+] Generating zone block for $domain"

    cat > "$outfile" <<EOF
${domain}:53 {
    import Base
    file ${zonefile}

    dnssec {
        key file ${keyfile} ${privfile}
    }

    import After
}

tls://${domain}:853 {
    import Base
    file ${zonefile}

    dnssec {
        key file ${keyfile} ${privfile}
    }

    import After
}

https://${domain}:8443 {
    import Base
    file ${zonefile}

    dnssec {
        key file ${keyfile} ${privfile}
    }

    import After
}

grpc://${domain}:9443 {
    import Base
    file ${zonefile}

    dnssec {
        key file ${keyfile} ${privfile}
    }

    import After
}
EOF

    # Update cache with new hash - ensure clean write
    current_hash=$(cat "$zonefile" | tr -d '\r' | sed 's/[[:space:]]*$//' | grep -v "IN.*SOA" | md5sum | cut -d' ' -f1)
    echo -n "$current_hash" > "$cachefile"
    chown coredns:coredns "$cachefile"

done

echo "[✅] All zone blocks generated."

# Execute SOA serial update only if files actually changed (not just key regeneration)
if [[ "$files_actually_changed" == true ]]; then
    echo "[*] Zone files were modified, updating SOA serials for ${#changed_zone_files[@]} zones..."
    if [[ -x "$UPDATE_SOA_SCRIPT" ]]; then
        "$UPDATE_SOA_SCRIPT" "${changed_zone_files[@]}"
        echo "[✅] SOA serials updated."
        
        # Recalculate hashes after SOA update to avoid mismatch on next run
        echo "[*] Updating cache hashes after SOA update..."
        for zonefile in "${changed_zone_files[@]}"; do
            filename="$(basename "$zonefile" .zone)"
            parent="$(basename "$(dirname "$zonefile")")"
            domain="${filename}.${parent}"
            cachefile="${CACHE_DIR}/${domain}.hash"
            
            # Recalculate hash excluding SOA serial
            updated_hash=$(cat "$zonefile" | tr -d '\r' | sed 's/[[:space:]]*$//' | grep -v "IN.*SOA" | md5sum | cut -d' ' -f1)
            echo -n "$updated_hash" > "$cachefile"
            chown coredns:coredns "$cachefile"
        done
        echo "[✅] Cache hashes updated."
    else
        echo "[⚠] SOA update script not found or not executable: $UPDATE_SOA_SCRIPT"
    fi
else
    echo "[ℹ] No zone files changed, skipping SOA serial update."
fi