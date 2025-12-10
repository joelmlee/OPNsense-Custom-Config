#!/bin/sh
#
# VPN Bypass - DNS-based VPN bypass for OPNsense
# Resolves domains to IPs and populates a PF table
#

DOMAIN_FILE="/usr/local/etc/vpn_bypass_domains.conf"
DISCOVERED_DOMAINS_FILE="/var/db/customconfig_vpnbypass_discovered.txt"
TABLE_NAME="customconfig_vpnbypass"
TEMP_FILE="/tmp/vpn_bypass_ips.tmp"
CONFIG_XML="/conf/config.xml"

COMMON_SUBDOMAINS="www"

# Check if a domain matches any configured wildcard
domain_matches_wildcards() {
    check_domain="$1"

    [ ! -f "$DOMAIN_FILE" ] && return 1

    while IFS= read -r line; do
        case "$line" in
            "#"*|"") continue ;;
            \*.*)
                base_domain="${line#\*.}"
                # Check if domain equals base or ends with .base
                case "$check_domain" in
                    "$base_domain"|*".$base_domain")
                        return 0
                        ;;
                esac
                ;;
        esac
    done < "$DOMAIN_FILE"

    return 1
}

configure() {
    # Ensure PF table exists
    /sbin/pfctl -t "$TABLE_NAME" -T show >/dev/null 2>&1 || {
        /sbin/pfctl -t "$TABLE_NAME" -T add 127.0.0.1 2>/dev/null
        /sbin/pfctl -t "$TABLE_NAME" -T delete 127.0.0.1 2>/dev/null
    }

    if [ -f "$DOMAIN_FILE" ]; then
        # Build list of subdomains to add
        temp_subs="/tmp/vpnbypass_subs.tmp"
        > "$temp_subs"

        while IFS= read -r line; do
            case "$line" in
                "#"*|"") continue ;;
                \*.*)
                    base_domain="${line#\*.}"
                    # Add root domain
                    echo "${base_domain}" >> "$temp_subs"
                    # Add common subdomains to temp file
                    for sub in $COMMON_SUBDOMAINS; do
                        echo "${sub}.${base_domain}" >> "$temp_subs"
                    done
                    # Try to flush Unbound cache for this zone
                    unbound-control -c /var/unbound/unbound.conf flush_zone "$base_domain" 2>/dev/null || true
                    ;;
            esac
        done < "$DOMAIN_FILE"

        # Clean up discovered domains that no longer match any wildcard
        if [ -f "$DISCOVERED_DOMAINS_FILE" ]; then
            temp_clean="/tmp/vpnbypass_clean.tmp"
            > "$temp_clean"
            while IFS= read -r domain; do
                [ -z "$domain" ] && continue
                if domain_matches_wildcards "$domain"; then
                    echo "$domain" >> "$temp_clean"
                else
                    echo "Removing stale domain: $domain"
                fi
            done < "$DISCOVERED_DOMAINS_FILE"
            mv "$temp_clean" "$DISCOVERED_DOMAINS_FILE"
        fi

        # Merge new base domains with cleaned discovered domains
        if [ -f "$DISCOVERED_DOMAINS_FILE" ]; then
            cat "$DISCOVERED_DOMAINS_FILE" >> "$temp_subs"
        fi
        sort -u "$temp_subs" > "$DISCOVERED_DOMAINS_FILE"
        rm -f "$temp_subs"
    fi

    echo "VPN Bypass configured"
}

resolve_domain() {
    domain="$1"
    drill "$domain" A 2>/dev/null | grep -E 'IN[[:space:]]+A[[:space:]]' | awk '{print $NF}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'
    drill "$domain" AAAA 2>/dev/null | grep -E 'IN[[:space:]]+AAAA[[:space:]]' | awk '{print $NF}' | grep -E '^[0-9a-fA-F:]+$'
}

update() {
    if [ ! -f "$DOMAIN_FILE" ]; then
        echo "Domain file not found: $DOMAIN_FILE"
        return 1
    fi

    > "$TEMP_FILE"

    while IFS= read -r line; do
        case "$line" in
            "#"*|"") continue ;;
        esac

        domain=$(echo "$line" | tr -d '[:space:]')
        [ -z "$domain" ] && continue

        case "$domain" in
            \*.*)
                base_domain="${domain#\*.}"
                resolve_domain "$base_domain" >> "$TEMP_FILE"
                for sub in $COMMON_SUBDOMAINS; do
                    resolve_domain "${sub}.${base_domain}" >> "$TEMP_FILE"
                done
                ;;
            *)
                resolve_domain "$domain" >> "$TEMP_FILE"
                ;;
        esac
    done < "$DOMAIN_FILE"

    if [ -f "$DISCOVERED_DOMAINS_FILE" ] && [ -s "$DISCOVERED_DOMAINS_FILE" ]; then
        echo "Resolving discovered domains..."
        while IFS= read -r domain; do
            [ -z "$domain" ] && continue
            resolve_domain "$domain" >> "$TEMP_FILE"
        done < "$DISCOVERED_DOMAINS_FILE"
    fi

    sort -u "$TEMP_FILE" -o "$TEMP_FILE"
    ip_count=$(wc -l < "$TEMP_FILE" | tr -d ' ')

    if [ -s "$TEMP_FILE" ]; then
        /sbin/pfctl -t "$TABLE_NAME" -T flush 2>/dev/null
        /sbin/pfctl -t "$TABLE_NAME" -T add -f "$TEMP_FILE" 2>/dev/null
        logger -t customconfig "VPN Bypass: Updated $TABLE_NAME with $ip_count IPs"
        echo "Updated PF table '$TABLE_NAME' with $ip_count IPs"
    else
        echo "No IPs resolved from domains"
    fi

    rm -f "$TEMP_FILE"
}

status() {
    echo "=== VPN Bypass Status ==="
    if /sbin/pfctl -t "$TABLE_NAME" -T show >/dev/null 2>&1; then
        count=$(/sbin/pfctl -t "$TABLE_NAME" -T show | wc -l | tr -d ' ')
        echo "PF Table '$TABLE_NAME': $count IPs"
        echo ""
        echo "Current IPs:"
        /sbin/pfctl -t "$TABLE_NAME" -T show
    else
        echo "PF Table '$TABLE_NAME' does not exist"
    fi

    echo ""
    echo "=== Discovered Domains ==="
    if [ -f "$DISCOVERED_DOMAINS_FILE" ] && [ -s "$DISCOVERED_DOMAINS_FILE" ]; then
        cat "$DISCOVERED_DOMAINS_FILE"
    else
        echo "No discovered domains yet"
    fi
}

discovered() {
    echo "{"
    echo '  "domains": ['
    if [ -f "$DISCOVERED_DOMAINS_FILE" ] && [ -s "$DISCOVERED_DOMAINS_FILE" ]; then
        first=1
        while IFS= read -r domain; do
            [ -z "$domain" ] && continue
            if [ $first -eq 1 ]; then
                echo "    \"$domain\""
                first=0
            else
                echo "    ,\"$domain\""
            fi
        done < "$DISCOVERED_DOMAINS_FILE"
    fi
    echo '  ],'

    if [ -f "$DISCOVERED_DOMAINS_FILE" ]; then
        count=$(wc -l < "$DISCOVERED_DOMAINS_FILE" | tr -d ' ')
    else
        count=0
    fi
    echo "  \"count\": $count"
    echo "}"
}

clear_discovered() {
    if [ -f "$DISCOVERED_DOMAINS_FILE" ]; then
        rm -f "$DISCOVERED_DOMAINS_FILE"
        echo "Cleared discovered domains"
    else
        echo "No discovered domains file"
    fi
}

add_domain() {
    domain="$1"
    if [ -z "$domain" ]; then
        echo "Usage: $0 add <domain>"
        return 1
    fi

    if [ -f "$DISCOVERED_DOMAINS_FILE" ] && grep -q "^${domain}$" "$DISCOVERED_DOMAINS_FILE" 2>/dev/null; then
        echo "Domain already in list: $domain"
    else
        echo "$domain" >> "$DISCOVERED_DOMAINS_FILE"
        echo "Added domain: $domain"
    fi

    ips=$(resolve_domain "$domain")
    if [ -n "$ips" ]; then
        echo "$ips" | while read -r ip; do
            /sbin/pfctl -t "$TABLE_NAME" -T add "$ip" 2>/dev/null
        done
        ip_count=$(echo "$ips" | wc -l | tr -d ' ')
        echo "Resolved $ip_count IPs for $domain"
    else
        echo "No IPs resolved for $domain"
    fi
}

case "$1" in
    configure) configure ;;
    update) update ;;
    status) status ;;
    discovered) discovered ;;
    clear) clear_discovered ;;
    add) add_domain "$2" ;;
    *) echo "Usage: $0 {configure|update|status|discovered|clear|add <domain>}"; exit 1 ;;
esac
