# WR30U: Minimal 237 OpenWrt 24.10 / Linux 6.6 / MTK mtwifi Firmware

This repository builds a deliberately small, single-purpose firmware image for the Xiaomi WR30U:

- 237 (padavanonly) `openwrt-24.10-6.6` branch;
- Linux 6.6;
- MediaTek proprietary `mtwifi`, plus HNAT and WARP;
- only the WR30U hanwckf U-Boot extended-partition layout;
- LuCI and the UPnP management page included, with **UPnP disabled by default**;
- no Passwall, SSR Plus, AdGuardHome, Samba, Docker, ttyd, traffic monitor, or similar extras.

This is neither an official OpenWrt image nor a prebuilt binary published by 237. GitHub Actions builds it from public source at pinned revisions. The MTK Wi-Fi stack includes proprietary drivers and firmware blobs; choosing it is an explicit tradeoff between wireless performance, auditability, and upstream support.

## Important: OpenWrt 24.10 security lifecycle

One practical limitation must be accepted: **official security updates for OpenWrt 24.10 end in September 2026**. OpenWrt officially recommends migrating to 25.12 before then; see the [OpenWrt 25.12.0 release notes](https://openwrt.org/releases/25.12/notes-25.12.0) and [security support status](https://openwrt.org/docs/guide-developer/security).

This repository intentionally completes the mature 237 `24.10 + 6.6 + mtwifi` setup now. **Migration to 25.12 is deferred and is not part of this build.** The 25.12 path will be evaluated separately later, and this image must not be treated as a maintenance-free long-term endpoint. Reassess the 237/MTK vendor stack's 25.12 path before September 2026. After EOL, do not keep using this firmware as an Internet-facing primary router unless a trustworthy source of security fixes exists.

## Pinned inputs

The build does not follow moving branch heads:

| Input | Pinned revision |
|---|---|
| `padavanonly/immortalwrt-mt798x-6.6` | `ec9ef10efc65da1e6d1de4e2c043c0e13d08eed8` |
| `immortalwrt/packages` | `50afba57f43f57ed94e8c117c40a343cd9929126` |
| `immortalwrt/luci` | `4936dfeddea460a4734fa4acdc68a9df1ace200c` |
| `openwrt/routing` | `946e9ff93be935fce6c03f4c02124833c35c2f56` |
| `openwrt/telephony` | `92892fa285360b8981f62bf4e0a097e6449e7e33` |

These pins keep the source inputs consistent between builds. GitHub runner images and toolchains may still change, so bit-for-bit reproducibility is not guaranteed. Every artifact also contains the complete `.config`, diffconfig, source/feed revisions, and `SHA256SUMS`.

## Why the profile is named `ubootmod`, not `112m`

The MT7981 defconfig at the pinned 237 commit still contains the obsolete symbol:

```text
xiaomi_mi-router-wr30u-112m
```

The actual device definition has been renamed to:

```text
xiaomi_mi-router-wr30u-ubootmod
```

Its DTS defines a `0x07000000` UBI partition (112 MiB), so `ubootmod` is the hanwckf multi-layout U-Boot **112m path** used by this project. The preparation script removes the stale symbol and verifies that only the valid profile is selected.

> Do not flash this project's images on the stock partition layout or after selecting the `default`/stock layout in U-Boot.

## Firmware contents

The retained core functionality includes:

- base OpenWrt/ImmortalWrt routing components: firewall4, dnsmasq, odhcpd, and Dropbear;
- LuCI with the lightweight default interface;
- MTK `kmod-mt_wifi`, `mtwifi-cfg`, `wifi-scripts`, and the matching LuCI pages;
- MTK HNAT and WARP;
- the legacy `kmod-ipt-nat` kernel compatibility module required by the 237 HNAT Kconfig (the active userspace firewall remains nftables/firewall4);
- nftables miniupnpd and the LuCI UPnP page;
- `iwinfo` for basic wireless status checks.

The script starts from the upstream MT7981 defconfig so the internal mtwifi/WARP Kconfig requirements are preserved. It then removes unrelated device selections and convenience packages before adding the small package set above. The open-source `mt76` packages inherited by the WR30U profile are explicitly excluded to avoid mixing them with the MTK vendor Wi-Fi stack.

`wifi-scripts` is intentionally retained even though this image does not use the mac80211/mt76 stack. It supplies `/sbin/wifi` and netifd's wireless helper, which `mtwifi-cfg` needs to create `/etc/config/wireless` on first boot and expose both MediaTek radios in LuCI.

On a clean first boot, both generated radios are visible in LuCI but disabled. Configure WPA2/WPA3 credentials before enabling them; this prevents the vendor defaults from briefly broadcasting unencrypted `ImmortalWrt-2.4G` and `ImmortalWrt-5G` networks.

[`patches/0001-wr30u-minimal-mtwifi-profile.patch`](patches/0001-wr30u-minimal-mtwifi-profile.patch) is the only intentional upstream source patch in this build. It narrows 237's broad default package set for MediaTek devices and replaces the WR30U ubootmod profile's default Wi-Fi packages with the mtwifi/HNAT/WARP and LuCI/UPnP set used here. The build fails immediately if this patch no longer applies cleanly to the pinned commit.

### UPnP default state

UPnP is installed in the image, but [`files/etc/uci-defaults/99-upnp-disabled`](files/etc/uci-defaults/99-upnp-disabled) applies three safeguards on first boot:

1. sets `upnpd.config.enabled=0`;
2. stops miniupnpd;
3. disables miniupnpd at boot.

Enable it manually in LuCI only when needed, and restrict the allowed ports and LAN ranges first. To enable it from the command line:

```sh
uci set upnpd.config.enabled='1'
uci commit upnpd
/etc/init.d/miniupnpd enable
/etc/init.d/miniupnpd restart
```

## Build with GitHub Actions

1. Open **Actions -> Build WR30U minimal mtwifi firmware -> Run workflow**.
2. Wait for the build to complete.
3. Download the `wr30u-237-24.10-6.6-mtwifi-minimal` artifact.
4. Extract it and verify the checksums:

   ```sh
   sha256sum -c SHA256SUMS
   ```

The primary image name must contain:

```text
xiaomi_mi-router-wr30u-ubootmod-squashfs-sysupgrade.bin
```

The current upstream `ubootmod` profile produces a `sysupgrade.bin`; it **does not produce a conventional `factory.bin`**. Do not substitute an old tutorial's filename or flash a `stock` image instead.

## Flashing boundaries

This repository assumes that the router already runs the hanwckf WR30U multi-layout U-Boot. Before flashing:

1. back up BL2, FIP, Factory/EEPROM, the current UBI, and other critical partitions, and store the backups away from the router;
2. verify that the device is a WR30U and that its current U-Boot/partition layout matches the 112m `ubootmod` layout;
3. run `sha256sum -c SHA256SUMS` on the downloaded files;
4. use `sysupgrade.bin` only when upgrading from a compatible OpenWrt/ImmortalWrt installation, never a `stock` profile;
5. when switching layouts for the first time or migrating from another partition scheme, do not blindly perform a normal sysupgrade. Follow that U-Boot's recovery instructions and prepare a wired recovery path.

For the first migration, do not retain the old configuration. This avoids carrying mt76 wireless settings or stale package state into the mtwifi system. Flashing always carries a risk of bricking the device; do not proceed without partition backups and a working recovery entry point.

## Post-flash checks

```sh
# Confirm vendor Wi-Fi / HNAT / WARP modules
lsmod | grep -E 'mt_wifi|hnat|warp'

# Confirm that UPnP is installed but neither running nor enabled
opkg list-installed | grep -E 'miniupnpd|luci-app-upnp'
uci -q get upnpd.config.enabled
/etc/init.d/miniupnpd enabled; echo "enabled_rc=$?"
/etc/init.d/miniupnpd running; echo "running_rc=$?"

# Confirm the device and root filesystem
ubus call system board
df -h
```

The expected `upnpd.config.enabled` value is `0`, and both miniupnpd checks should return nonzero status codes. Compare wireless performance on the same channel, channel width, distance, and client, testing both upload and download rather than relying on a single Internet speed test.

## Local configuration check

A complete build is best run on AMD64 Linux; the 237 upstream project does not recommend building directly on macOS. With an adjacent 237 source tree whose feeds are already installed, run:

```sh
./scripts/prepare-config.sh /path/to/immortalwrt-source
```

After generating `.config`, the script verifies that WR30U ubootmod is the only selected device, mtwifi/HNAT/WARP/UPnP are present, and excluded large packages have not reappeared.
