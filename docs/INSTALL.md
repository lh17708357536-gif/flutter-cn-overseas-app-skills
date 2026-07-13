# 安装与接入

本仓库是 Markdown 规范包，无需构建。按你的 AI 助手选一种接入方式。

## Claude Code

Skill 的规范安装位置是用户级目录 `~/.claude/skills/`：
```bash
git clone <THIS_REPO_URL>
cp -R flutter-cn-overseas-app-skills/skills/* ~/.claude/skills/
```
Claude Code 会读取每个 `SKILL.md` 的 frontmatter `description`，在相关任务时自动加载。验证：
```bash
ls ~/.claude/skills/   # 应看到 flutter-multi-region-dev 等 13 项
```
之后在会话里描述任务（如"做一个国内+海外都上架的 Flutter App"），助手会命中 `flutter-multi-region-dev` 路由。也可显式说"参照 flutter-multi-region-dev skill"。

> 若只想项目级生效（不污染全局），复制到项目内 `.claude/skills/` 亦可。

## Codex（及读 AGENTS.md 的 agent）

本仓库根目录的 [`AGENTS.md`](../AGENTS.md) 是标准入口。两种用法：
1. **作为独立参考仓库**：clone 后让 Codex 把它作为上下文目录，指示"遵循 AGENTS.md 的路由表"。
2. **并入你的项目**：把 `skills/` 与 `AGENTS.md` 放进你的工程根（或子目录），Codex 读 `AGENTS.md` 获取路由与路径映射。

## Cursor / Windsurf / 其他

- 把本仓库 `skills/` 目录纳入项目可见范围。
- 在你的规则文件（如 Cursor 的 `.cursor/rules/`）里加一句：
  > 多区域 Flutter/NestJS 任务，先读 `skills/flutter-multi-region-dev/SKILL.md`，按其路由加载子 skill；跨 skill 铁律见 `skills/_shared/rules.md`。
- 任何能读文件的 agent 都可直接打开 `skills/<name>/SKILL.md`——纯 Markdown，无专有格式。

## 路径映射

Skill 正文中的 `~/.claude/skills/X` ≡ 本仓库 `skills/X`。非 Claude Code 用户按此理解引用即可（详见 `AGENTS.md`）。

## 更新

```bash
cd flutter-cn-overseas-app-skills && git pull
cp -R skills/* ~/.claude/skills/     # Claude Code 用户重新覆盖
```

## 定制

- 所有 `<PLACEHOLDER>` 换成你的项目值（IP / 域名 / 包名 / AppID 等）。
- 建议在你自己项目的 `CLAUDE.md` / `AGENTS.md` 里固化项目特定信息（备案号、服务器、模块清单），skill 保持通用。
- 换供应商（如阿里云 OSS → 腾讯云 COS、JPush → HMS）时，改对应 skill 章节即可；欢迎把通用化改动提 PR 回上游。
