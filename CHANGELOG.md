# Changelog

遵循 [Semantic Versioning](https://semver.org/),格式参考 [Keep a Changelog](https://keepachangelog.com/)。

## [Unreleased] — v0.1.0(开发中)

### Added
- 核心 `ccpoint.zsh`:provider 加载、fzf/select 调度、子 shell 启动、防串号、退出回退默认端点
- 声明式 provider API(关联数组 `ccpoint_p`)+ 可选 `ccpoint_start_<name>` / `ccpoint_stop_<name>` 生命周期钩子(容纳"起本地代理 + 健康检查 + trap 清理"类复杂 provider)
- 4 个示例 provider:`deepseek` / `glm`(Z.ai)/ `opencode_go`(本地代理示例)/ `yescode`
- fzf 软依赖(`(( $+commands[fzf] ))`)+ 数字菜单降级(避开 zsh `select` 多列对中文宽字符的对齐 bug)
- 子命令:`ccpoint`(交互)/ `ccpoint <name>`(直选)/ `ccpoint list` / `ccpoint init` / `ccpoint help`
- 安全:key 不落 provider 文件,用 `auth_var` 从环境变量取;AUTH_TOKEN 模式自动清空 `ANTHROPIC_API_KEY` 防串号
