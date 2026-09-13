# SYSU Bandwidth Aggregation

中大校园网多账号带宽聚合方案，基于 OpenWrt / ImmortalWrt。

通过 MacVLAN + MiniEAP 建立多路认证连接，用 nftables 按新连接分配 WAN，再由 CAKE / autorate 控制排队延迟。五路并发下载曾达到约 **460 Mbps**；单条连接仍只使用一路带宽。

目前提供五路 WAN 的参考脚本、配置示例，以及可选的 sing-box 网站分流工具。实测设备为雅典娜 RE-CS-02，移植时需要调整接口和依赖，暂无一键安装器。

## 文档

- [多账号认证与连接级分流](docs/03-five-wan.md)
- [CAKE 参数与测速](docs/04-cake-and-measurement.md)
- [CPU 分流与 NSS](docs/05-cpu-and-nss.md)
- [Steam 下载排查](docs/07-steam.md)
- [sing-box 网站分流](docs/08-singbox.md)
- [备份与恢复](docs/09-operations.md)

[路由器参考脚本](reference/router/README.md) · [测试数据](evidence/README.md)

设备笔记：[RE-CS-02 刷机](docs/01-firmware.md) · [QCN9074 CN 修复](docs/02-qcn9074-cn.md) · [三频 Wi-Fi](docs/06-wifi.md)

## 网站分流工具

需要 Node.js 22+，无第三方 npm 依赖。

```sh
git clone https://github.com/ZyPulse-zy/sysu-bandwidth-aggregation.git
cd sysu-bandwidth-aggregation
npm run panel
```

打开终端显示的地址，为网站分类选择节点，也可添加自定义域名。保存结果在 `local/`，不会自动应用到路由器。示例节点需要替换；配置格式和部署步骤见 [sing-box 文档](docs/08-singbox.md)。

`npm run generate` 直接生成配置，`npm test` 运行测试。

## 致谢

参考了 [KumaTea](https://github.com/KumaTea/MentoHUST-SYSU-Guide)、[DreamOfStars](https://github.com/DreamOfStars/SYSU-Network-Guide)、[undefined443](https://github.com/undefined443/openwrt-minieap-sysu) 等中大校园网项目。[完整参考](docs/10-references.md)。

[MIT](LICENSE)，第三方代码见 [许可证说明](THIRD_PARTY_NOTICES.md)。使用账号与接入方式须符合所在校区的网络规定。
