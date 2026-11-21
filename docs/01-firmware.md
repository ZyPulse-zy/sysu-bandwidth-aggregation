# RE-CS-02 固件与恢复记录

适用记录：JDCOS-4.3.1.r4317 → ImmortalWrt，保留原 GPT 布局。

## 入口与备份

这台设备的备份是在厂商 Telnet 标志启用后取得的，ART 反映当时的状态。考虑更换固件前，先根据设备硬件版本核对可用的管理和恢复入口。

写入前核对设备树、eMMC 容量与扇区大小、分区标签和起止位置；网页曾返回 RE-SS-02，实际设备树为 `jdcloud,re-cs-02`。

备份至少包括 ART、APPSBL 双份、APPSBLENV、BOOTCONFIG 双份、启动链和无线/PHY 固件，以及主备 GPT。复制到电脑后比对大小、SHA256 和 GPT CRC。boot0/boot1、RPMB 与数据分区需另列清单，关键分区备份不等于全盘克隆。

## 写入记录

- APPSBL 双份各写入 655360 字节专用 U-Boot。
- 固件按 HLOS/rootfs 的实际边界写入并回读。
- 启动槽只修改 BOOTCONFIG 对应字段。
- 原 log 文件系统用作 extroot，未重新分区或格式化。

分区号与镜像尺寸可能随固件布局变化，不能直接套用其他教程的 `dd of=`。写入错误会导致无法启动，应先确认恢复入口。

## 版本

| 项目 | 版本 |
| --- | --- |
| U-Boot | chenxin527，2016.01-3011049，2026-08-16 |
| 镜像 | VIKINGYFY，main-26.09.11-07.21.17 |
| 源码 | 90448eeb2b8f5d172caedfe6d96ab3bacb058c09 |
| 内核 | Linux 6.18.44 |

该镜像还需处理 [CN 无线问题](02-qcn9074-cn.md)及匹配 CAKE 模块。选择替代固件时同时核对设备支持、rootfs 容量和布局。

来源：[刷机教程](https://github.com/lgs2007m/Actions-OpenWrt/blob/main/Tutorial/JDCloud-AX1800-Pro_AX6600-Athena.md)、[U-Boot](https://github.com/chenxin527/uboot-qsdk12.5-build)、[镜像构建](https://github.com/VIKINGYFY/OpenWRT-CI)、[LibWrt](https://github.com/LiBwrt/LibWrt)。
