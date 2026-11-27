#!/bin/sh
set -eu

ZT_VERSION="${ZT_VERSION:-1.16.2}"
BUILD_ROOT="${BUILD_ROOT:-/root/build}"
PREFIX="${PREFIX:-/usr/local}"
ZT_HOME="${ZT_HOME:-/var/db/zerotier-one}"
BUILD_ONLY="${BUILD_ONLY:-0}"

SRC_DIR="${BUILD_ROOT}/ZeroTierOne-${ZT_VERSION}"
ARCHIVE="${BUILD_ROOT}/ZeroTierOne-${ZT_VERSION}.tar.gz"
URL="https://github.com/zerotier/ZeroTierOne/archive/refs/tags/${ZT_VERSION}.tar.gz"
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PATCH_FILES="
${SCRIPT_DIR}/patches/netbsd-build-system.patch
${SCRIPT_DIR}/patches/netbsd-tap-device.patch
${SCRIPT_DIR}/patches/netbsd-managed-routes.patch
"
JOBS=$(sysctl -n hw.ncpu 2>/dev/null || echo 1)
RC_SCRIPT=/etc/rc.d/zerotier_one

if [ "$(id -u)" -ne 0 ]; then
	echo "run as root" >&2
	exit 1
fi

if [ ! -c /dev/tap ]; then
	echo "/dev/tap is missing; the kernel needs the tap(4) pseudo-device" >&2
	exit 1
fi

for patch_file in $PATCH_FILES; do
	if [ ! -f "$patch_file" ]; then
		echo "missing patch: $patch_file" >&2
		exit 1
	fi
done

if ! command -v gmake >/dev/null 2>&1; then
	pkgin -y install gmake
fi

mkdir -p "$BUILD_ROOT"

if [ -d "$SRC_DIR" ]; then
	mv "$SRC_DIR" "${SRC_DIR}.bak.$(date +%Y%m%d%H%M%S)"
fi

attempt=1
until ftp -o "$ARCHIVE" "$URL"; do
	if [ "$attempt" -ge 3 ]; then
		echo "download failed: $URL" >&2
		exit 1
	fi
	attempt=$((attempt + 1))
	sleep 5
done
tar -xzf "$ARCHIVE" -C "$BUILD_ROOT"

cd "$SRC_DIR"
for patch_file in $PATCH_FILES; do
	patch -p1 < "$patch_file"
done
gmake -j"$JOBS"
./zerotier-one -v

if [ "$BUILD_ONLY" = "1" ]; then
	echo "build completed: ${SRC_DIR}/zerotier-one"
	exit 0
fi

install -d -o root -g wheel -m 755 "${PREFIX}/sbin"
install -d -o root -g wheel -m 755 "${PREFIX}/bin"
BACKUP_BINARY=""
if [ -f "${PREFIX}/sbin/zerotier-one" ]; then
	BACKUP_BINARY="${PREFIX}/sbin/zerotier-one.bak.$(date +%Y%m%d%H%M%S)"
	cp -p "${PREFIX}/sbin/zerotier-one" "$BACKUP_BINARY"
fi

SERVICE_ACTION=start
if "$RC_SCRIPT" status >/dev/null 2>&1; then
	SERVICE_ACTION=restart
fi

install -m 0755 -o root -g wheel zerotier-one "${PREFIX}/sbin/zerotier-one"
ln -sf "${PREFIX}/sbin/zerotier-one" "${PREFIX}/sbin/zerotier-cli"
ln -sf "${PREFIX}/sbin/zerotier-one" "${PREFIX}/bin/zerotier-idtool"

install -d -o root -g wheel -m 700 "$ZT_HOME"

cat > "$RC_SCRIPT" <<EOF
#!/bin/sh
#
# PROVIDE: zerotier_one
# REQUIRE: NETWORKING DAEMON dhcpcd wpa_supplicant ntpd
# KEYWORD: shutdown

# ZeroTier One built from source on NetBSD.

\$_rc_subr_loaded . /etc/rc.subr

name="zerotier_one"
rcvar=\$name
command="${PREFIX}/sbin/zerotier-one"
command_args="-d ${ZT_HOME}"
pidfile="${ZT_HOME}/zerotier-one.pid"
start_precmd="zerotier_one_precmd"

zerotier_one_precmd()
{
	install -d -o root -g wheel -m 700 ${ZT_HOME}
	_n=0
	while [ \$_n -lt 30 ]; do
		netstat -rn -f inet 2>/dev/null | grep -q '^default' && break
		sleep 1
		_n=\$((_n + 1))
	done
}

load_rc_config \$name
run_rc_command "\$1"
EOF

chown root:wheel "$RC_SCRIPT"
chmod 555 "$RC_SCRIPT"

install -d -o root -g wheel -m 755 /etc/rc.conf.d
echo "zerotier_one=YES" > /etc/rc.conf.d/zerotier_one

restore_backup() {
	if [ -n "$BACKUP_BINARY" ]; then
		"$RC_SCRIPT" stop >/dev/null 2>&1 || true
		install -m 0755 -o root -g wheel "$BACKUP_BINARY" "${PREFIX}/sbin/zerotier-one"
		rm -f "${ZT_HOME}/zerotier-one.pid" "${ZT_HOME}/zerotier-one.port"
		"$RC_SCRIPT" start
	fi
}

if [ "$SERVICE_ACTION" = "start" ]; then
	rm -f "${ZT_HOME}/zerotier-one.pid" "${ZT_HOME}/zerotier-one.port"
fi

if ! "$RC_SCRIPT" "$SERVICE_ACTION"; then
	restore_backup
	echo "ZeroTier service failed after installation; the previous binary was restored when available" >&2
	exit 1
fi

sleep 3
"${PREFIX}/sbin/zerotier-one" -v
"${PREFIX}/sbin/zerotier-cli" status || true
if ! "$RC_SCRIPT" status; then
	restore_backup
	echo "ZeroTier health check failed after installation; the previous binary was restored when available" >&2
	exit 1
fi
