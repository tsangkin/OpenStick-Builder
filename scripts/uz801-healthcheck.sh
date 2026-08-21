#!/bin/sh

set +e

echo '=== UZ801 SMS appliance health check ==='
echo

echo '[system]'
uname -a
printf 'Debian: '
cat /etc/debian_version 2>/dev/null || true
printf 'Hostname: '
hostname 2>/dev/null || true

echo
echo '[temperature]'
found_temp=0
for z in /sys/class/thermal/thermal_zone*; do
    [ -r "$z/temp" ] || continue
    found_temp=1
    type=$(cat "$z/type" 2>/dev/null)
    temp=$(cat "$z/temp" 2>/dev/null)
    echo "$z type=${type:-unknown} temp=${temp:-unknown}"
done
[ "$found_temp" -eq 1 ] || echo 'No thermal zones found'

echo
echo '[network links]'
ip -br link 2>/dev/null || true

echo
echo '[addresses]'
ip -br addr 2>/dev/null || true

echo
echo '[default routes]'
ip route show default 2>/dev/null || true

echo
echo '[NetworkManager connections]'
nmcli -f NAME,TYPE,DEVICE,AUTOCONNECT connection show 2>/dev/null || true

echo
echo '[modem list]'
mmcli -L 2>/dev/null || true

echo
echo '[modem 0 summary]'
mmcli -m 0 2>/dev/null || true

echo
echo '[bearers]'
mmcli -m 0 --list-bearers 2>/dev/null || true

echo
echo '[services]'
for svc in NetworkManager ModemManager simadmin usb-gadget adbd-tcp; do
    printf '%-16s ' "$svc"
    systemctl is-active "$svc.service" 2>/dev/null || true
done

echo
echo '[SimAdmin listening ports]'
ss -lntp 2>/dev/null | grep -E 'simadmin|:80 |:3000 |:8080 |:5555 ' || true

echo
echo '[VoLTE/IMS note]'
echo 'This image intentionally has no preconfigured Internet APN.'
echo 'LTE registration, modem IMS/VoLTE capability and SMS are not disabled by this check.'
echo 'Do not create a generic mobile-data connection unless testing it intentionally.'
