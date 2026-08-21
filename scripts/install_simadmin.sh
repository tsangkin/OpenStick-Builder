#!/bin/sh -e

CHROOT=${CHROOT:-$(pwd)/rootfs}
SIMADMIN_VERSION=${SIMADMIN_VERSION:-latest}
TMPDIR=$(mktemp -d)
ARCHIVE="${TMPDIR}/simadmin-aarch64.tar.gz"
EXTRACT_DIR="${TMPDIR}/extract"

cleanup() {
    rm -rf "${TMPDIR}"
}
trap cleanup EXIT

mkdir -p "${EXTRACT_DIR}" "${CHROOT}/opt/simadmin"

if [ "${SIMADMIN_VERSION}" = "latest" ]; then
    URL="https://github.com/3899/SimAdmin/releases/latest/download/simadmin-aarch64.tar.gz"
else
    case "${SIMADMIN_VERSION}" in
        v*) TAG="${SIMADMIN_VERSION}" ;;
        *) TAG="v${SIMADMIN_VERSION}" ;;
    esac
    URL="https://github.com/3899/SimAdmin/releases/download/${TAG}/simadmin-aarch64.tar.gz"
fi

echo "Downloading SimAdmin (${SIMADMIN_VERSION}) for aarch64..."
if ! curl -fL --retry 3 --connect-timeout 20 "${URL}" -o "${ARCHIVE}"; then
    echo "Direct GitHub download failed, trying fallback proxy..."
    curl -fL --retry 3 --connect-timeout 20 "https://ghproxy.net/${URL}" -o "${ARCHIVE}"
fi

tar -xzf "${ARCHIVE}" -C "${EXTRACT_DIR}"

if [ ! -f "${EXTRACT_DIR}/simadmin" ] || [ ! -d "${EXTRACT_DIR}/www" ]; then
    echo "SimAdmin release archive has an unexpected layout" >&2
    exit 1
fi

install -m 0755 "${EXTRACT_DIR}/simadmin" "${CHROOT}/opt/simadmin/simadmin"
rm -rf "${CHROOT}/opt/simadmin/www"
cp -a "${EXTRACT_DIR}/www" "${CHROOT}/opt/simadmin/www"

if [ -f "${EXTRACT_DIR}/meta.json" ]; then
    install -m 0644 "${EXTRACT_DIR}/meta.json" "${CHROOT}/opt/simadmin/meta.json"
fi

echo "SimAdmin installed into rootfs."
