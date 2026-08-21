#!/bin/sh -e

CHROOT=${CHROOT=$(pwd)/rootfs}
RELEASE=${RELEASE=trixie}
HOST_NAME=${HOST_NAME=uz801-sms}

rm -rf ${CHROOT}

debootstrap --foreign --arch arm64 \
    --keyring /usr/share/keyrings/debian-archive-keyring.gpg ${RELEASE} ${CHROOT}

cp $(which qemu-aarch64-static) ${CHROOT}/usr/bin

chroot ${CHROOT} qemu-aarch64-static /bin/bash /debootstrap/debootstrap --second-stage

cat << EOF > ${CHROOT}/etc/apt/sources.list
deb http://deb.debian.org/debian ${RELEASE} main contrib non-free-firmware
deb http://deb.debian.org/debian-security/ ${RELEASE}-security main contrib non-free-firmware
deb http://deb.debian.org/debian ${RELEASE}-updates main contrib non-free-firmware
EOF

mount -t proc proc ${CHROOT}/proc/
mount -t sysfs sys ${CHROOT}/sys/
mount -o bind /dev/ ${CHROOT}/dev/
mount -o bind /dev/pts/ ${CHROOT}/dev/pts/
mount -o bind /run ${CHROOT}/run/

cp scripts/setup.sh ${CHROOT}
chroot ${CHROOT} qemu-aarch64-static /bin/sh -c /setup.sh

# cleanup
for a in proc sys dev/pts dev run; do
    umount ${CHROOT}/${a}
done;

rm -f ${CHROOT}/setup.sh
echo -n > ${CHROOT}/root/.bash_history

echo ${HOST_NAME} > ${CHROOT}/etc/hostname
sed -i "/localhost/ s/$/ ${HOST_NAME}/" ${CHROOT}/etc/hosts

# setup systemd services
cp -a configs/system/* ${CHROOT}/etc/systemd/system
mkdir -p ${CHROOT}/etc/systemd/system/multi-user.target.wants

# Keep the existing RNDIS USB gadget for the maintenance network.
# Debian's stock adbd.service may create its own USB gadget, which would
# conflict with usb-gadget.service, so use a dedicated TCP adbd service.
ln -sf /dev/null ${CHROOT}/etc/systemd/system/adbd.service
ln -sf ../adbd-tcp.service ${CHROOT}/etc/systemd/system/multi-user.target.wants/adbd-tcp.service
ln -sf ../uz801-maintenance-firewall.service ${CHROOT}/etc/systemd/system/multi-user.target.wants/uz801-maintenance-firewall.service
ln -sf ../simadmin.service ${CHROOT}/etc/systemd/system/multi-user.target.wants/simadmin.service

# dnsmasq is used only to hand out an address on usb0; no DNS proxy, NAT or
# default gateway is offered to the maintenance PC.
mkdir -p ${CHROOT}/etc/dnsmasq.d
cat << EOF > ${CHROOT}/etc/dnsmasq.d/20-uz801-usb-maintenance.conf
port=0
interface=usb0
bind-dynamic
dhcp-range=192.168.5.2,192.168.5.20,255.255.255.0,12h
dhcp-option=3
dhcp-option=6
dhcp-authoritative
EOF
ln -sf /lib/systemd/system/dnsmasq.service ${CHROOT}/etc/systemd/system/multi-user.target.wants/dnsmasq.service

# This appliance must never act as a router. Disabling host forwarding does
# not disable modem registration, SMS, IMS or VoLTE inside the modem stack.
mkdir -p ${CHROOT}/etc/sysctl.d
cat << EOF > ${CHROOT}/etc/sysctl.d/20-uz801-appliance.conf
net.ipv4.ip_forward=0
net.ipv6.conf.all.forwarding=0
EOF

# Give ModemManager a lightweight systemd-level recovery policy. SimAdmin has
# its own modem health/recovery logic, so no second periodic watchdog is added.
mkdir -p ${CHROOT}/etc/systemd/system/ModemManager.service.d
cat << EOF > ${CHROOT}/etc/systemd/system/ModemManager.service.d/20-uz801-restart.conf
[Service]
Restart=on-failure
RestartSec=5s
EOF

cp -a scripts/msm-firmware-loader.sh ${CHROOT}/usr/sbin
install -m 0755 scripts/uz801-healthcheck.sh ${CHROOT}/usr/local/sbin/uz801-healthcheck

# setup NetworkManager
# Only USB maintenance networking is preconfigured. No generic LTE Internet
# connection/APN is installed, so NetworkManager will not auto-dial mobile data.
# This does not disable modem registration, SIM/SMS access, or modem-managed IMS/VoLTE.
cp configs/*.nmconnection ${CHROOT}/etc/NetworkManager/system-connections
chmod 0600 ${CHROOT}/etc/NetworkManager/system-connections/*
mkdir -p ${CHROOT}/etc/NetworkManager/conf.d
cat << EOF > ${CHROOT}/etc/NetworkManager/conf.d/20-uz801-wifi-powersave.conf
[connection]
wifi.powersave=2
EOF

# enable autoconnect for usb0
cat << EOF > ${CHROOT}/etc/udev/rules.d/99-nm-usb0.rules
SUBSYSTEM=="net", ACTION=="add|change|move", ENV{DEVTYPE}=="gadget", ENV{NM_UNMANAGED}="0"
EOF

# Limit persistent journal size to reduce eMMC writes while retaining reboot diagnostics.
mkdir -p ${CHROOT}/etc/systemd/journald.conf.d ${CHROOT}/var/log/journal
cat << EOF > ${CHROOT}/etc/systemd/journald.conf.d/20-uz801.conf
[Journal]
Storage=persistent
Compress=yes
SystemMaxUse=32M
SystemKeepFree=64M
RuntimeMaxUse=16M
MaxRetentionSec=7day
RateLimitIntervalSec=30s
RateLimitBurst=500
EOF

# install kernel
wget -O - http://mirror.postmarketos.org/postmarketos/v24.06/aarch64/linux-postmarketos-qcom-msm8916-6.6-r5.apk \
    | tar xkzf - -C ${CHROOT} --exclude=.PKGINFO --exclude=.SIGN* 2>/dev/null

mkdir -p ${CHROOT}/boot/extlinux
cp configs/extlinux.conf ${CHROOT}/boot/extlinux

# copy custom dtb's
cp dtbs/* ${CHROOT}/boot/dtbs/qcom

# create missing directory
mkdir -p ${CHROOT}/lib/firmware/msm-firmware-loader

# integrate latest SimAdmin aarch64 release into the image
CHROOT=${CHROOT} sh -e scripts/install_simadmin.sh

# update fstab
echo "PARTUUID=80780b1d-0fe1-27d3-23e4-9244e62f8c46\t/boot\text2\tdefaults,noatime\t0 2" > ${CHROOT}/etc/fstab

# backup rootfs
tar cpzf rootfs.tgz --exclude="usr/bin/qemu-aarch64-static" -C rootfs .
