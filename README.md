# WR30U：237 OpenWrt 24.10 / Linux 6.6 / MTK mtwifi 极简固件

这个仓库为小米 WR30U 构建一份用途明确的自用固件：

- 237（padavanonly）的 `openwrt-24.10-6.6` 分支；
- Linux 6.6；
- MediaTek 闭源 `mtwifi`，以及 HNAT / WARP；
- 只构建 WR30U 的 hanwckf U-Boot 扩展分区布局；
- 保留 LuCI 与 UPnP 管理页面，但 **UPnP 默认关闭**；
- 不加入 Passwall、SSR Plus、AdGuardHome、Samba、Docker、ttyd、流量监控等附加服务。

这不是 OpenWrt 官方固件，也不是 237 发布的现成二进制。它是从公开源码和固定 revision 在 GitHub Actions 中自行构建的固件。MTK Wi-Fi 栈包含闭源驱动/固件 blob；使用它是在无线性能、可审计性与上游支持之间做出的主动取舍。

## 重要：24.10 的安全生命周期

不过有一个现实点要接受：**OpenWrt 24.10 官方会在 2026 年 9 月停止安全更新**。官方已经明确建议在 2026 年 9 月前迁移到 25.12（见 [OpenWrt 25.12.0 发布说明](https://openwrt.org/releases/25.12/notes-25.12.0) 与 [安全支持状态](https://openwrt.org/docs/guide-developer/security)）。

本仓库这一次仍然有意完成成熟的 237 `24.10 + 6.6 + mtwifi` 方案，**本次不迁移 25.12**。25.12 会在后续单独评估，不能把这个镜像当作多年不维护的终点。到 2026 年 9 月前应重新检查 237/MTK vendor 栈的 25.12 路线；EOL 后若没有可信的安全补丁来源，不应继续把本固件作为公网主路由长期运行。

## 固定的输入

构建不会直接跟随分支 HEAD 漂移：

| 输入 | 固定 revision |
|---|---|
| `padavanonly/immortalwrt-mt798x-6.6` | `ec9ef10efc65da1e6d1de4e2c043c0e13d08eed8` |
| `immortalwrt/packages` | `50afba57f43f57ed94e8c117c40a343cd9929126` |
| `immortalwrt/luci` | `4936dfeddea460a4734fa4acdc68a9df1ace200c` |
| `openwrt/routing` | `946e9ff93be935fce6c03f4c02124833c35c2f56` |
| `openwrt/telephony` | `92892fa285360b8981f62bf4e0a097e6449e7e33` |

这些 pin 让每次构建对应到同一组源码输入，但 GitHub runner/toolchain 仍可能更新，因此这里不承诺逐 bit 可复现。每个 artifact 会同时保存完整 `.config`、diffconfig、feed/source revision 与 `SHA256SUMS`。

## 为什么 profile 叫 `ubootmod`，不是 `112m`

237 当前固定 commit 的 `defconfig/mt7981-ax3000.config` 还残留旧 symbol：

```text
xiaomi_mi-router-wr30u-112m
```

但实际设备定义已经改名为：

```text
xiaomi_mi-router-wr30u-ubootmod
```

它的 DTS 将 UBI 分区定义为 `0x07000000`，即 112 MiB，所以这里的 `ubootmod` 就是本项目所说的 hanwckf multi-layout U-Boot **112m 路线**。构建脚本会主动删除失效的旧 symbol，并验证最终只选择这个有效 profile。

> 不要把本项目产物用于 stock layout，也不要在 U-Boot 中选择 `default`/stock 分区后刷入。

## 固件内容

保留的核心能力包括：

- OpenWrt/ImmortalWrt 基础路由组件：firewall4、dnsmasq、odhcpd、Dropbear；
- LuCI（轻量默认界面）；
- MTK `kmod-mt_wifi`、`mtwifi-cfg` 与对应 LuCI 页面；
- MTK HNAT 与 WARP；
- nftables 版本的 miniupnpd 与 LuCI UPnP 页面；
- `iwinfo`，用于基本无线状态检查。

脚本从上游 MT7981 defconfig 起步，以免漏掉 mtwifi/WARP 的内部 Kconfig；随后清除上游 convenience config 中预选的其他设备和附加包，再加入上述小集合。WR30U profile 默认带入的开源 `mt76` 驱动包也会被显式排除，避免与 MTK vendor Wi-Fi 栈混装。

[`patches/0001-wr30u-minimal-mtwifi-profile.patch`](patches/0001-wr30u-minimal-mtwifi-profile.patch) 是这次构建唯一主动修改的上游源码 patch：它收窄 237 对所有 MediaTek 设备设置的宽泛默认包，并把 WR30U ubootmod profile 的默认 Wi-Fi 包明确替换为 mtwifi/HNAT/WARP 和本项目的 LuCI/UPnP 集合。patch 若不能干净应用到固定 commit，构建会直接失败。

### UPnP 默认状态

UPnP 软件确实被编进镜像，但首次启动时 [`files/etc/uci-defaults/99-upnp-disabled`](files/etc/uci-defaults/99-upnp-disabled) 会再次执行三层保护：

1. `upnpd.config.enabled=0`；
2. 停止 miniupnpd；
3. 禁止 miniupnpd 开机启动。

需要时可在 LuCI 中手动启用；启用前应限制允许的端口和 LAN 范围。命令行启用方式为：

```sh
uci set upnpd.config.enabled='1'
uci commit upnpd
/etc/init.d/miniupnpd enable
/etc/init.d/miniupnpd restart
```

## 在 GitHub Actions 构建

1. 把本仓库推到 GitHub。
2. 打开 **Actions → Build WR30U minimal mtwifi firmware → Run workflow**。
3. 构建完成后下载 `wr30u-237-24.10-6.6-mtwifi-minimal` artifact。
4. 解压并先验证：

   ```sh
   sha256sum -c SHA256SUMS
   ```

主固件文件名应包含：

```text
xiaomi_mi-router-wr30u-ubootmod-squashfs-sysupgrade.bin
```

当前上游 `ubootmod` profile 生成的是 `sysupgrade.bin`，**不会生成一个名为 `factory.bin` 的常规产物**。不要因为旧教程或旧文件名而改刷 `stock` 镜像。

## 刷写边界

本仓库假设设备已经安装 hanwckf 的 WR30U multi-layout U-Boot。刷写前必须：

1. 备份 BL2、FIP、Factory/EEPROM 和当前 UBI 等关键分区，并把备份放到路由器之外；
2. 确认设备确实是 WR30U，且当前 U-Boot/分区布局与 112m `ubootmod` 匹配；
3. 对下载后的文件执行 `sha256sum -c SHA256SUMS`；
4. 从兼容的 OpenWrt/ImmortalWrt 系统升级时使用 `sysupgrade.bin`，不要使用 `stock` profile；
5. 首次切换布局或从其他分区方案迁移时，不要盲目套用普通 sysupgrade；应从 U-Boot 恢复界面按该 U-Boot 的说明操作，并准备有线恢复路径。

建议首次迁移不保留旧配置，避免把 mt76 无线配置或旧软件包状态带入 mtwifi 系统。刷写本身有变砖风险；没有分区备份和恢复入口时不要继续。

## 刷写后的检查

```sh
# 确认 vendor Wi-Fi / HNAT / WARP 模块
lsmod | grep -E 'mt_wifi|hnat|warp'

# 确认 UPnP 已安装但未运行、未启用
opkg list-installed | grep -E 'miniupnpd|luci-app-upnp'
uci -q get upnpd.config.enabled
/etc/init.d/miniupnpd enabled; echo "enabled_rc=$?"
/etc/init.d/miniupnpd running; echo "running_rc=$?"

# 确认设备与根分区
ubus call system board
df -h
```

预期 `upnpd.config.enabled` 为 `0`，后两个返回码均非 0。无线性能测试应在相同信道、频宽、距离和客户端下进行，并分别测试上下行，避免只看一次互联网 Speedtest。

## 本地配置检查

完整编译建议使用 AMD64 Linux；237 上游不推荐直接在 macOS 上构建。在已经安装 feeds 的 237 源码树旁，可运行：

```sh
./scripts/prepare-config.sh /path/to/immortalwrt-source
```

脚本会在生成 `.config` 后检查：唯一设备是否为 WR30U ubootmod、mtwifi/HNAT/WARP/UPnP 是否存在，以及已禁止的大包是否意外回归。
