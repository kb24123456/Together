# Codex Memory Workflow

## 结论

本项目使用四层机制承接 Claude 历史上下文，并让 Codex 形成可持续记忆：

1. `AGENTS.md`：强规则和项目执行约束。
2. `docs/PROJECT_MEMORY.md`：当前项目进度、决策和可复用事实。
3. `.agents/skills/`：高频工作流。
4. Codex Memories：可选，用于自动沉淀用户偏好和稳定习惯。

Chronicle 暂不开启。

## 开始复杂任务

要求 Codex 先读：

```text
AGENTS.md
PRODUCT_SPEC.md
DEVELOPMENT_GUIDELINES.md
DESIGN_GUIDELINES.md
docs/PROJECT_MEMORY.md
```

如果任务涉及具体模块，再继续读取相关 `Features / Domain / Services / Persistence / Sync` 文件。

## 阶段性完成后

使用项目 Skill：

```text
使用 stage-memory-update 工作流收尾：总结本阶段，更新 docs/PROJECT_MEMORY.md，并指出是否需要沉淀新 Skill。
```

适用场景：

- 完成一个大功能。
- 完成一次长时间 bug 修复。
- 完成架构调整、迁移、性能优化或复杂调研。
- 完成跨会话阶段任务。

## Claude 历史资料承接方式

- Claude 留下的根目录文档可作为上下文来源。
- `.claude/worktrees/*` 是历史 worktree，不能直接等同当前主分支事实。
- 任何来自历史计划的结论，写入 `PROJECT_MEMORY.md` 前都要和当前根目录文档或代码校验。

## 可选全局配置

如果决定开启 Codex Memories，在 `~/.codex/config.toml` 中加入：

```toml
[features]
memories = true

[memories]
generate_memories = true
use_memories = true
```

说明：

- 这是用户级配置，不提交到项目仓库。
- 关键项目事实仍必须写入 `docs/PROJECT_MEMORY.md`。
- 团队和项目强规则仍必须写入 `AGENTS.md`。
