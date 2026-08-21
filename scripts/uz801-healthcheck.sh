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
printf 'IPv4 forwarding: '
sysctl -n net.ipv4.ip_forward 2>/dev/null || true

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
echo '[USB maintenance DHCP]'
systemctl is-active dnsmasq.service 2>/dev/null || true
grep -v '^#' /etc/dnsmasq.d/20-uz801-usb-maintenance.conf 2>/dev/null || true

echo
echo '[ADB maintenance firewall]'
systemctl is-active uz801-maintenance-firewall.service 2>/dev/null || true
iptables -S INPUT 2>/dev/null | grep 5555 || true

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
for svc in NetworkManager ModemManager simadmin usb-gadget adbd-tcp dnsmasq uz801-maintenance-firewall; do
    printf '%-28s ' "$svc"
    systemctl is-active "$svc.service" 2>/dev/null || true
done

echo
echo '[SimAdmin / ADB listening ports]'
ss -lntp 2>/dev/null | grep -E 'simadmin|:80 |:3000 |:8080 |:5555 ' || true

echo
echo '[cellular policy]'
echo 'Expected: Wi-Fi is the Internet/default route; usb0 is maintenance-only.'
echo 'Expected: there is no preconfigured generic Internet APN or auto-dial LTE data profile.'
echo 'LTE registration, SIM/SMS and modem-managed IMS/VoLTE are intentionally left enabled.'
echo 'ModemManager has systemd crash recovery; SimAdmin provides modem health recovery.'
echo 'No custom timer restarts modem remoteproc/DSP.'
