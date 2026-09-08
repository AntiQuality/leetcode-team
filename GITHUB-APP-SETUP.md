# GitHub App 维护配置

普通用户使用发行版内置配置，无需填写开发者参数。

自行维护发行版时，在 GitHub 注册项目专用 App：

- 启用 Device flow 和用户访问 token 过期。
- 关闭 webhook。
- Repository permissions：Contents 为 Read and write，Metadata 为 Read-only。
- 不请求 Administration、组织或账号权限。
- 如需支持其他房主安装，允许其他账号安装该 App。

将公开 Client ID 与 App slug 写入 `Resources/github-app.json`：

```json
{"clientID":"YOUR_PUBLIC_CLIENT_ID","slug":"your-github-app-slug"}
```

仓库中的实际配置用于官方发行版登录。Client ID 和 slug 是公开应用标识，不是用户凭证；替换或删除会影响登录和安装授权。

GitHub 如要求生成 App 私钥，应由维护者自行保管。不得将私钥、Client secret、用户 token 或浏览器会话提交到源码仓库或安装包。客户端使用 Device flow 及其 refresh token，不需要开发者私钥或 Client secret。

房主自行创建私有 `leetcode-team-sync` 仓库，并只为该仓库安装 App。队员接受协作者邀请后连接同一仓库。
