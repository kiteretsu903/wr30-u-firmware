#!/bin/sh
set -eu

if [ "$#" -gt 1 ]; then
	printf 'usage: %s [openwrt-source-dir]\n' "$0" >&2
	exit 2
fi

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source_dir=${1:-.}
source_dir=$(CDPATH= cd -- "$source_dir" && pwd)
upstream_seed="$source_dir/defconfig/mt7981-ax3000.config"
project_fragment="$repo_dir/configs/wr30u-minimal.config"
profile_patch="$repo_dir/patches/0001-wr30u-minimal-mtwifi-profile.patch"

[ -f "$upstream_seed" ] || {
	printf 'missing upstream seed: %s\n' "$upstream_seed" >&2
	exit 1
}

if git -C "$source_dir" apply --check "$profile_patch" 2>/dev/null; then
	git -C "$source_dir" apply "$profile_patch"
elif ! git -C "$source_dir" apply --reverse --check "$profile_patch" 2>/dev/null; then
	printf 'profile patch neither applies cleanly nor appears already applied\n' >&2
	exit 1
fi

# The upstream seed is a multi-device convenience config with many optional
# packages. Keep its MTK driver Kconfig, but clear all selected devices and
# packages before adding this project's intentionally small selection.
awk '
	function disable(line, symbol) {
		symbol = line
		sub(/^CONFIG_/, "", symbol)
		sub(/=y$/, "", symbol)
		print "# CONFIG_" symbol " is not set"
	}
	/^CONFIG_TARGET_DEVICE_[^=]*=y$/ { disable($0); next }
	/^CONFIG_PACKAGE_[^=]*=y$/ { disable($0); next }
	/^CONFIG_TARGET_mediatek_mt7981=y$/ { disable($0); next }
	/^CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_xiaomi_mi-router-wr30u-112m=y$/ { disable($0); next }
	{ print }
' "$upstream_seed" > "$source_dir/.config"

printf '\n' >> "$source_dir/.config"
sed '/^[[:space:]]*#/d; /^[[:space:]]*$/d' "$project_fragment" >> "$source_dir/.config"

make -C "$source_dir" defconfig

required='CONFIG_TARGET_mediatek_filogic=y
CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_xiaomi_mi-router-wr30u-ubootmod=y
CONFIG_PACKAGE_kmod-mt_wifi=y
CONFIG_PACKAGE_kmod-mediatek_hnat=y
CONFIG_PACKAGE_kmod-ipt-nat=y
CONFIG_PACKAGE_kmod-warp=y
CONFIG_PACKAGE_mtwifi-cfg=y
CONFIG_PACKAGE_luci-app-mtwifi-cfg=y
CONFIG_PACKAGE_luci-app-upnp=y
CONFIG_PACKAGE_miniupnpd-nftables=y'

printf '%s\n' "$required" | while IFS= read -r line; do
	[ -z "$line" ] && continue
	grep -Fqx "$line" "$source_dir/.config" || {
		printf 'required config was not retained: %s\n' "$line" >&2
		exit 1
	}
done

for forbidden in \
	CONFIG_PACKAGE_luci-app-adguardhome \
	CONFIG_PACKAGE_luci-app-passwall \
	CONFIG_PACKAGE_luci-app-ssr-plus \
	CONFIG_PACKAGE_luci-app-ttyd \
	CONFIG_PACKAGE_luci-app-wrtbwmon \
	CONFIG_PACKAGE_kmod-mt7915e \
	CONFIG_PACKAGE_samba4-server \
	CONFIG_PACKAGE_dockerd; do
	if grep -Eq "^${forbidden}=[ym]$" "$source_dir/.config"; then
		printf 'forbidden package unexpectedly selected: %s\n' "$forbidden" >&2
		exit 1
	fi
done

selected_devices=$(grep -Ec '^CONFIG_TARGET_DEVICE_.*=y$' "$source_dir/.config" || true)
[ "$selected_devices" -eq 1 ] || {
	printf 'expected exactly one selected device, found %s\n' "$selected_devices" >&2
	exit 1
}

printf 'configuration ready: WR30U ubootmod (112m layout), MTK mtwifi, HNAT/WARP, UPnP disabled at runtime\n'
