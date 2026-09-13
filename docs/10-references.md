# 参考项目与版本关系

检查日期：2026-09-13。下列项目是思路、实现或历史参考，不代表作者为本仓库背书。只引用必要结论和链接，没有复制整篇教程。

| 项目 | 参考价值 | 不直接照搬的部分 |
| --- | --- | --- |
| [KumaTea/MentoHUST-SYSU-Guide](https://github.com/KumaTea/MentoHUST-SYSU-Guide) | 中大路由器认证历史、从 MentoHUST 转向 MiniEAP 的经验 | 仓库已归档；旧硬件/IPv6说明不能当当前验证 |
| [KumaTea/minieap](https://github.com/KumaTea/minieap) | 校园适配客户端方向 | 分支和实际包来源须单独核对 |
| [DreamOfStars/SYSU-Network-Guide](https://github.com/DreamOfStars/SYSU-Network-Guide) | R2S 示例、SDK 与 MiniEAP 安装顺序 | R2S 的接口名、架构和包不能直接用于 RE-CS-02 |
| [undefined443/openwrt-minieap-sysu](https://github.com/undefined443/openwrt-minieap-sysu) | 中大适配包、SDK 构建流程 | 宿舍适用范围与 opkg/ipk 示例须按当前固件转换 |
| [bakabaka9405/minieap-sysu-east-openwrt](https://github.com/bakabaka9405/minieap-sysu-east-openwrt) | 对服务端周期性用户名请求和状态机限制的说明 | 不能据 AX6S/极路由测试宣称所有设备稳定 |
| [RenAhsAcme/SYSU-Network-Solution](https://github.com/RenAhsAcme/SYSU-Network-Solution) | 较完整的构建/认证/整形文档组织 | 其 OpenClash/qosify 与固件配置不等于本机 CAKE/sing-box/PBR |
| [updateing/minieap](https://github.com/updateing/minieap) | MiniEAP 上游与 RJv3 插件机制 | 凭据和校区参数必须本地设置 |
| [lynxthecat/cake-autorate](https://github.com/lynxthecat/cake-autorate) | 动态调速、日志指标；本机使用 3.2.1 | 动态整形不是所有固定线路的必需品 |
| [Linux scaling](https://docs.kernel.org/networking/scaling.html) | RPS/RSS/XPS 机制 | 掩码收益以具体硬件 A/B 为准 |
| [OpenWrt usteer](https://github.com/openwrt/usteer) | k/v 引导、客户端协作 | 不强制终端服从，也不等同无缝漫游 |
| [MetaCubeX/meta-rules-dat](https://github.com/MetaCubeX/meta-rules-dat) | sing-box 原生 SRS | 固定提交和哈希，不自动引入未经验证更新 |
| [ACL4SSR](https://github.com/ACL4SSR/ACL4SSR) / [blackmatrix7](https://github.com/blackmatrix7/ios_rule_script) | 主流网站类别组织 | 只参考分类，不替换整套网络架构 |
| [sing-box](https://github.com/SagerNet/sing-box) | 透明代理与 selector | 公开包只生成候选，需目标核心验证 |

固件、U-Boot、ath11k 与 NSS 的精确来源列在各章节。社区项目的“能跑满”“稳定两年”等属于各自环境，不能拿来填充本机缺失的实测结果。

## 许可证处理

原创文档、编译器和维护脚本以 MIT 发布。没有打包 MiniEAP、CAKE autorate、sing-box、Mihomo、固件、模块或 SRS 数据库的二进制。实际使用这些上游时遵循其各自许可证；不因本仓库 MIT 就改变上游许可证。

ath11k 补丁带上游上下文及独立声明，详见 [第三方说明](../THIRD_PARTY_NOTICES.md)。公开实验摘要由本机记录整理，不包含第三方文章全文或私人原始数据。
