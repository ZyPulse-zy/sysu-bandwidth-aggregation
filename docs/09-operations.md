# 备份与恢复

网络配置修改前保留有线管理连接，并将备份复制到电脑、核对 SHA256。

- **设备备份**：ART、GPT、引导等原始分区，用于固件恢复。
- **配置备份**：network、firewall、认证文件、服务及脚本。
- **代理备份**：DNS、核心配置、规则和一致性 FakeIP 缓存；缓存应在停止核心后复制。

配置归档不能代替原始分区备份。BusyBox tar 的选项与 GNU tar 不完全一致，可按目标环境使用 `-X` 排除文件。

## 网络事务

[transaction.sh](../reference/router/transaction.sh)配合独立 guard，按期限、boot ID 和验证文件决定提交或回滚。SSH 断开后 guard 仍需运行；每次变更必须提供对应的 undo，checkpoint 本身不会自动恢复所有状态。

测试通过其清理入口结束，并检查 active transaction、临时 nft 表、监听端口和服务。远端测试还需分别撤销主机防火墙与云防火墙规则。

## 日常检查

重启后先检查六路认证、租约、路由表和十二个常规 CAKE 队列。下面的脚本只读，输出接口、mark 规则、桶数及 CAKE 速率：

```sh
ssh root@router 'sh -s' < reference/router/inspect-athena.sh
```

正常情况下 WAN1–5 各 60 桶，WAN6 为 0。故障和恢复期间按健康状态重新分桶。游戏资格看 `/tmp/router-project-health/wan6-game-control.json`，备用线看 `athena_game_fallback` 的活动集合与 `agameifbN` 实际过滤器。无线、代理和原生 IPv6 分别通过真实客户端请求核对。

已部署这套服务的 Athena 可在维护窗口停止并禁用 `athena-bulk-forward`，回到常规 CAKE 转发。核对流表与下载放行规则已撤下，随后检查 WAN6 游戏、WAN1 IPv6 和代理服务。内核升级时重新核对 CAKE ABI 和无线驱动。

单路故障只恢复对应实例。高频日志放 RAM 并轮转；需要跨重启保留的记录另行归档。

故障定位顺序：

```text
管理链路 → carrier → EAP → DHCP/网关 → mark/路由/NAT → DNS → CAKE → 代理节点
```
