# Steam 慢：先辨认是哪一段路径

先分开 Steam 客户端速度、Windows 网卡接收、路由器 WAN RX、CAKE 输出。它们统计窗口与协议层不同，差值不自动等于某一种重传/丢包。

## 三个实际结论

1. **约 350 Mbps 不是 70×5 的基准硬限制。** 同时刻五路 CAKE 已升到约 100 Mbps；CPU0 softirq 压力较高，后续 RPS 对照改善最忙核心。
2. **Clash 规则 DIRECT 仍会经过本机 Mihomo。** 真正旁路要确认 CDN 套接字归属 Steam 自己，而不只是配置界面显示 Direct。
3. **确认旁路不等于确认提速。** 本机窄域名 Windows 代理例外在正常退出并重启 Steam 后生效，但本轮网卡 RX 从 370.01 Mbps 到 368.87/366.86 Mbps，没有明显收益，最终恢复原代理设置。

早期只刷新 Windows 系统代理例外，旧 Steam 进程并未采用；重启后主要 CDN TCP 连接归属 Steam，Mihomo 中相应连接消失。只为已观察到的下载域名设置例外，商店、社区等其他业务保留代理。没有强杀、修改路由器或开启额外 benchmark。

前后 CDN 地址、内容块与采样长度变化，以上是路径验证和短观察，不是严格配对性能证明。暂停/继续本身也曾让同一路径达到约 395 Mbps，不能把所有改善归因于绕过 Clash。

## HTTP 保活的小实验

在 Mihomo v1.19.29 本地复现：普通 HTTP 请求只带 `Connection: keep-alive` 时代理要求关闭连接；额外带 `Proxy-Connection: keep-alive` 时能复用。源码有对应判断，但没有采集真实 Steam 请求头证明它触发了该机制。2 字节回环实验不是吞吐测试。

TCP keepalive、HTTP 连接复用、DNS 并发连接竞速是不同机制。不要因为参数名含 keep-alive 或 tcp-concurrent 就认定能增加 Steam 下载流数。

建议排查顺序：客户端限速/磁盘→实际套接字路径→CDN 与连接数量→每 WAN/CAKE 真实速率→逐核 CPU→一次有限的同条件旁路。无重复收益就恢复，不继续叠加代理例外、全局 DNS 或 governor 修改。

来源：[Mihomo v1.19.29 HTTP 入站](https://github.com/MetaCubeX/mihomo/blob/v1.19.29/listener/http/proxy.go)、[Steam 官方排查](https://help.steampowered.com/en/faqs/view/5AC5-8056-E88F-F3FF)。
