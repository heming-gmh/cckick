# 贡献指南

感谢你有兴趣给 ccpoint 贡献!这是 deliberately small 的纯 zsh 工具,我们想保持它轻量——能一个 `source` 就用、不跑 proxy、不碰 `settings.json`、退出即净。

## 提 PR 前

1. **语法**:`zsh -n ccpoint.zsh` 无报错
2. **shellcheck**:`shellcheck ccpoint.zsh examples/*.zsh`(trap/关联数组相关误报可用 `# shellcheck disable=...` 抑制)
3. **测试**:`make test`(或 `zsh tests/run.zsh`)全绿
4. **provider 文件永不含真实 key**:用 `auth_var` 从环境变量取

## 加 provider 模板

欢迎往 `examples/` 加更多 provider。每个文件:
- 只声明 `ccpoint_p` 关联数组 + 可选 `ccpoint_start_<name>` / `ccpoint_stop_<name>` 钩子
- **不含真实 key**,用 `auth_var` 指向一个环境变量
- 文件名是合法 shell 标识符(`[a-z_][a-z0-9_]*`),即 provider 名

## commit message

简洁清晰,中英文都行。示例:`add provider: openrouter` / `fix: AUTH_TOKEN 模式未清 API_KEY 导致串号`。

## 设计约束(改核心前请读)

ccpoint 的核心卖点是默认且唯一的语义:**子 shell 启动 + 退出回退 + 不跑 proxy + 不碰 settings.json + 不污染父 shell env**。改动若削弱这些(比如加常驻进程、改 settings.json、往父 shell export),请先开 issue 讨论。

## 行为准则

见 [CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md)。参与即代表同意遵守。
