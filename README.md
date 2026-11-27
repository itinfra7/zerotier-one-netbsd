# ZeroTierOne for NetBSD

Build and install upstream ZeroTierOne 1.16.2 on NetBSD with three NetBSD-specific source patches.

## Overview

ZeroTierOne source code is not vendored in this repository. `install.sh` downloads the selected upstream release archive, applies the patches in a fixed order, builds the daemon with `gmake`, validates the resulting binary, installs it, and registers a NetBSD `rc.d` service.

The patch set is maintained against ZeroTierOne 1.16.2. `ZT_VERSION` can select another release, but a different release is not supported until all patches have been checked against that source tree.

Upstream ZeroTierOne 1.16.2 does not build on NetBSD as released. Its NetBSD makefile and tap driver predate the current source tree. The patches below make the generic BSD build and tap driver work on NetBSD instead.

## Included Source Changes

### Build system

`patches/netbsd-build-system.patch` changes `Makefile` and `ext/prometheus-cpp-lite-1.0/core/include/prometheus/text_serializer.h`.

- Builds NetBSD through `make-bsd.mk` with platform identifier 8 (`ZT_PLATFORM_NETBSD`) instead of the stale `make-netbsd.mk`, which references objects that no longer exist in the source tree.
- Includes `<cmath>` instead of `<math.h>` in the vendored Prometheus serializer. NetBSD `<math.h>` defines `isnan` and `isinf` as macros, which break the `std::isnan` and `std::isinf` calls.

### TAP device

`patches/netbsd-tap-device.patch` changes `osdep/EthernetTap.cpp` and `osdep/BSDEthernetTap.cpp`.

- Uses `BSDEthernetTap` on NetBSD instead of the obsolete `NetBSDEthernetTap`, which targets an old tap interface API.
- Opens the `/dev/tap` cloning device and reads the new interface name with `TAPGIFNAME`, so the number of networks is not limited by the `/dev/tapN` nodes that exist.
- Sets the MAC address with `ifconfig <tap> link <mac> active`, because NetBSD `ifconfig` has no `lladdr` keyword and ignores `link` without `active`.
- Does not run `ifconfig destroy` on shutdown. NetBSD destroys a cloned tap interface when its descriptor is closed.
- Runs a single reader thread without CPU pinning and without `getifmaddrs(3)`, as on OpenBSD. NetBSD has neither `pthread_np.h` nor `getifmaddrs(3)`. Address-resolution multicast groups are derived from the assigned IP addresses.
- Joins the reader threads before closing the tap and shutdown descriptors on all BSD platforms, which prevents descriptor teardown races during shutdown.

### Managed routes

`patches/netbsd-managed-routes.patch` changes `osdep/ManagedRoute.cpp`.

- Uses `RTF_LLDATA` where other BSDs use `RTF_LLINFO`, which NetBSD removed.
- Advances through the socket addresses of routing messages with `RT_ROUNDUP`, because NetBSD pads each address to eight bytes.

## Requirements

- NetBSD with the `tap(4)` pseudo-device (present in `GENERIC`)
- root privileges
- outbound HTTPS access to GitHub
- the NetBSD base toolchain (GCC), `ftp`, `tar`, and `patch`
- `pkgin`; the installer installs `gmake` when it is not already available

## Install

Run as root:

```sh
sh install.sh
```

Default settings:

```sh
ZT_VERSION=1.16.2
BUILD_ROOT=/root/build
PREFIX=/usr/local
ZT_HOME=/var/db/zerotier-one
BUILD_ONLY=0
```

Settings can be overridden in the environment:

```sh
BUILD_ROOT=/tmp/zerotier-build PREFIX=/usr/pkg sh install.sh
```

To download, patch, build, and validate without installing files or changing service state:

```sh
BUILD_ONLY=1 sh install.sh
```

The installer writes `/etc/rc.d/zerotier_one` and `/etc/rc.conf.d/zerotier_one` (`zerotier_one=YES`), then starts or restarts the service. When the new binary fails to start, the previous binary is restored if one existed.

## Service And Diagnostics

```sh
/etc/rc.d/zerotier_one status
/etc/rc.d/zerotier_one start
/etc/rc.d/zerotier_one restart
/etc/rc.d/zerotier_one stop
```

Check ZeroTier status and join a network through the installed CLI:

```sh
zerotier-cli status
zerotier-cli join <network-id>
```

Each joined network appears as a `tapN` interface:

```sh
ifconfig -a
```

## Tested

NetBSD 10.1 amd64 with GCC 10.5.0:

- clean build and installation with `install.sh`
- daemon start, service restart, and shutdown through `rc.d`
- connection to the ZeroTier root servers and `ONLINE` status
- tap creation with the ZeroTier MAC address, MTU 2800, and automatic removal on network leave and daemon exit
- IPv4 and IPv6 address assignment and removal, address enumeration, and derivation of the ARP multicast group
- managed route creation through `route(8)` and the routing socket parser

Traffic across an authorized network was not tested.

## License And Credits

ZeroTierOne remains subject to its upstream license. The source patch files are distributed under MPL-2.0, and repository-local installer and documentation files are distributed under the MIT License described in `LICENSE`.

- ZeroTierOne by ZeroTier, Inc.: https://github.com/zerotier/ZeroTierOne
- NetBSD installer and NetBSD source patches: itinfra7
