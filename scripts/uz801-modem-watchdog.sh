#!/bin/sh

set +e

TAG=uz801-modem-watchdog

log() {
    logger -t "$TAG" "$*"
}

# ModemManager may legitimately need time after boot/remoteproc startup.
# This watchdog intentionally performs only a software-level recovery.
if ! systemctl is-active --quiet ModemManager.service; then
    log "ModemManager is inactive; restarting service"
    systemctl restart ModemManager.service
    exit 0
fi

if ! mmcli -L 2>/dev/null | grep -q '/Modem/'; then
    log "No modem exposed by ModemManager; restarting service only"
    systemctl restart ModemManager.service
    exit 0
fi

STATE=$(mmcli -m 0 2>/dev/null | sed -n "s/.*state: '\([^']*\)'.*/\1/p" | head -n 1)
if [ "$STATE" = "failed" ]; then
    log "Modem state is failed; restarting ModemManager service only"
    systemctl restart ModemManager.service
    exit 0
fi

exit 0
