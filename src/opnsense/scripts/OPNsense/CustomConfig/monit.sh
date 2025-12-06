#!/bin/sh
#
# Monit Process Monitor configuration for OPNsense
# Ensures monitrc has proper daemon settings and reloads monit
#

MONITRC="/usr/local/etc/monitrc"
MONIT_DROPIN="/usr/local/etc/monit.opnsense.d/customconfig.conf"

configure() {
    # Ensure monitrc has proper daemon settings
    if ! grep -q "set daemon" "$MONITRC" 2>/dev/null; then
        cat > "$MONITRC" << 'EOF'
# Monit configuration - managed by Custom Config plugin
set daemon 120
set httpd unixsocket /var/run/monit.sock allow localhost

include /usr/local/etc/monit.opnsense.d/*.conf
EOF
        chmod 600 "$MONITRC"
        echo "Created monitrc with daemon settings"
    fi

    # Ensure drop-in directory exists
    mkdir -p /usr/local/etc/monit.opnsense.d

    # Check if our config file exists and has content
    if [ -f "$MONIT_DROPIN" ] && [ -s "$MONIT_DROPIN" ]; then
        # Reload monit
        if pgrep -q monit; then
            pkill monit
            sleep 1
        fi
        /usr/local/bin/monit 2>/dev/null
        echo "Monit reloaded with custom process monitors"
    else
        echo "No custom Monit processes configured"
    fi
}

status() {
    echo "=== Monit Status ==="
    if pgrep -q monit; then
        /usr/local/bin/monit summary 2>/dev/null || echo "Monit running but cannot get summary"
    else
        echo "Monit is not running"
    fi
}

case "$1" in
    configure)
        configure
        ;;
    status)
        status
        ;;
    *)
        echo "Usage: $0 {configure|status}"
        exit 1
        ;;
esac
