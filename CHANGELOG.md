# Changelog

## Unreleased

### Fixed

- ZeroTier could be non-functional after a reboot even though the daemon was running and `zerotier-cli listnetworks` reported the network as `OK`. The `tap0` interface came up with the `OACTIVE` flag set (output queue stalled), no packets were transmitted or received, and peers showed `Host is down` / incomplete ARP entries. Restarting the service cleared the condition.
- The generated `rc.d` script started the daemon as soon as the `NETWORKING` and `DAEMON` stages completed. Because `dhcpcd` runs in the background (`-q`), the daemon could start before the uplink had an address and default route, so `tap0` was created while the network was still being configured.

### Changed

- `/etc/rc.d/zerotier_one` now declares `REQUIRE: NETWORKING DAEMON dhcpcd wpa_supplicant ntpd`.
- Before starting the daemon, the service now waits up to 30 seconds for an IPv4 default route to appear, then starts regardless so that offline boots are not blocked.

### Notes

- Existing installations need to re-run `install.sh` (or apply the same two changes to `/etc/rc.d/zerotier_one` manually) to pick up the fix.
- If `tap0` still reports `OACTIVE` after a clean boot with this change, the cause is in the tap device handling rather than in boot ordering, and `patches/netbsd-tap-device.patch` should be investigated.
