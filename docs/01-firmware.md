# 从 r4317 迁移：先识别，再备份，再写入

## 实际结果

设备为 RE-CS-02，原厂 JDCOS-4.3.1.r4317。没有主动升级原厂系统。通过已登录的本机管理接口开启 Telnet 后取得 root，完成关键备份，再安装专用 U-Boot 和适配原布局的 ImmortalWrt。最终运行时识别 `jdcloud,re-cs-02`；早期静态网页配置曾返回 RE-SS-02，不能拿网页字符串代替设备树识别。

本机开门路线参考 V-2333 的端口转发接口方法：先检查当前版本、接口签名和原有规则；获明确许可后通过 `set_port_forward` 入口调用设备自带 `factory_hm info telnet 1` 和 `telnetd`，清理临时转发条目，再验证真实 root 会话。这里只记录本机成功路径，不提供无人值守批量开门或远程扫描器。来源帖所写版本号不能自动等同于 r4317；旧 service/dropbear 教程未覆盖此版本。

**一个必须诚实记录的例外：**Telnet 开关调用发生在完整备份之前，且涉及厂商持久化标志。ART 备份是开启该开关之后取得，不能称为开关前原始 ART。对于下一台设备，优先采用能先读取/备份的入口；若无法做到，应明确此证据边界，而不是把事后备份包装成“从未改变”。

## 写入门槛

1. WAN 拔线、有线管理，记录 model/compatible、启动参数、挂载、eMMC 容量和扇区大小、MTD/块设备及各分区标签/起止/大小。
2. 按实际标签识别 ART、APPSBL 双份、APPSBLENV、BOOTCONFIG 双份、SBL/QSEE/DEVCFG/RPM/CDT、无线/PHY 固件及恢复相关配置。识别 boot0/boot1、RPMB 是否存在，不能假定已覆盖。
3. 保存主 GPT、条目和磁盘末尾备份 GPT；核对 CRC、容量和内核看到的布局。
4. 每份备份下载到电脑，比对大小与 SHA256。活动文件系统的原始镜像要注明一致性；必要时在 U-Boot 下离线读取并重复核对。
5. 每次写入单独核对镜像哈希、目标标签、长度和布局，事先具备恢复入口。没有可靠备份与标签映射就停止。

本案例保留 GPT，未改 ART 来修无线；APPSBL 双份各写专用 655360 字节 U-Boot。工厂镜像按本机 HLOS/rootfs 边界写入并回读。启动槽仅改 BOOTCONFIG 对应字段；不是清空整分区。原有 log 文件系统被用作 extroot，未格式化。这里故意不提供固定分区号或可直接复制的 `dd of=` 命令：分区号、镜像尺寸和教程年代不具有跨设备安全性。

备份覆盖关键原始分区与配置，不是完整全盘克隆；部分数据分区只有文件级归档，存储区、swap、RPMB 未完整复制。恢复能力必须按清单描述。

## 版本记录与选择教训

- U-Boot：chenxin527 构建 2016.01-3011049（2026-08-16），实际进入恢复网页并识别硬件。
- 镜像：VIKINGYFY `IPQ60XX-WIFI-YES-VIKINGYFY-main-26.09.11-07.21.17`，源码 `90448eeb2b8f5d172caedfe6d96ab3bacb058c09`，Linux 6.18.44。
- 后续发现无线 CN 规则和缺少匹配 CAKE 模块，需要额外维护。这是迁移历史，不是长期固件推荐排行榜。
- 较新的 LibWrt 成品可能大于本机原 rootfs 容量；版本较稳不代表分区适配。不能混用另一套 GPT 与 U-Boot 来解决体积问题。

来源：[lgs2007m 教程](https://github.com/lgs2007m/Actions-OpenWrt/blob/main/Tutorial/JDCloud-AX1800-Pro_AX6600-Athena.md)、[V-2333 原帖](https://www.right.com.cn/forum/thread-8477667-1-1.html)、[专用 U-Boot](https://github.com/chenxin527/uboot-qsdk12.5-build)、[镜像构建](https://github.com/VIKINGYFY/OpenWRT-CI)、[LibWrt](https://github.com/LiBwrt/LibWrt)。发布历史可能变化，按固定提交/标签核验，不直接执行在线脚本。
