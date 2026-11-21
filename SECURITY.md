# 安全报告

请通过 GitHub 的 [私密漏洞报告](https://github.com/ZyPulse-zy/sysu-bandwidth-aggregation/security/advisories/new) 提交本项目的安全问题。描述受影响的版本、触发条件和影响。公开 Issue 适用于普通缺陷，附件请使用最小脱敏样本。

面板监听本机回环地址，供本机用户操作。把它通过反向代理或端口转发暴露到其他主机前，应自行配置访问控制。候选文件可能包含真实节点凭据，保存在 Git 忽略的 `local/` 目录。

公开配置和日志前，可使用 `npm run audit -- --staged` 检查暂存快照，再人工核对实际差异。[贡献指南](CONTRIBUTING.md)
