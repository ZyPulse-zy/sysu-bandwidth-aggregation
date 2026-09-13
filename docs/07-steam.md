# Steam 下载排查

依次检查客户端限速与磁盘、下载连接的实际路径、CDN 与连接数、每 WAN 吞吐和 CAKE 速率，最后看逐核 CPU。客户端、网卡和路由器的统计窗口不同，应在相近时间段比较。

## 350 Mbps 是否被 base 限制

一次约 350 Mbps 的下载中，五路 CAKE 已升到约 100 Mbps，CPU0 softirq 较高。下载 base=70 Mbps 并未将总速率锁在 350 Mbps；后续 [RPS 对照](05-cpu-and-nss.md)降低了 CPU0 压力。

## Clash 的 DIRECT 与真正旁路

DIRECT 仍由本机 Mihomo 转发。判断是否旁路，需要看 CDN TCP 套接字属于 Steam 还是 Mihomo。

测试中，Windows 系统代理例外在正常退出并重启 Steam 后生效；只刷新代理设置时，旧进程仍使用原路径。例外范围限于已观察到的下载域名，商店与社区保留原代理。

旁路前网卡接收为 370.01 Mbps，之后为 368.87/366.86 Mbps，未见明显提速。CDN、内容块和采样时长不完全一致，这组结果用于确认路径，不能证明代理对所有下载都没有影响。[数据](../evidence/steam-proxy.csv)。

Mihomo v1.19.29 的 HTTP 入站对 `Proxy-Connection: keep-alive` 有专门处理，但未捕获真实 Steam 请求头确认该机制影响下载。TCP keepalive、HTTP 复用与并发下载连接数也不是同一参数。

参考：[Mihomo HTTP 入站](https://github.com/MetaCubeX/mihomo/blob/v1.19.29/listener/http/proxy.go)、[Steam 下载排查](https://help.steampowered.com/en/faqs/view/5AC5-8056-E88F-F3FF)。
