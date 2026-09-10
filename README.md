# Tibo Radar

一个运行在本机的 Codex 福利重置预测雷达。它读取公开的 Tibo / Codex
重置信号、历史事件和 OpenAI 状态事件，分别估算：

- 未来 24 / 48 小时发生全局额度重置的概率；
- 未来 24 / 48 小时普发 banked reset（重置卡）的概率；
- 两者至少发生一个的综合概率。

第一版只读公开信息，不登录 X，不读取或兑换你的 Codex 重置卡。

## 当前阶段

项目正在开发 `v0.1.0`。第一版会提供命令行快照、本地网页和 macOS
系统通知。详细范围见 [`docs/requirements.md`](docs/requirements.md)。

## 计划中的运行方式

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -e .
tibo-radar snapshot
tibo-radar serve --open
```

## 数据来源

- `codex-reset.com` 提供的公开 forecast、timeline 与 feed API；
- OpenAI Status 的公开状态数据；
- 原始 Tibo 帖子的公开链接，用于展示证据。

第三方数据可能延迟或中断，因此每次预测都会显示数据新鲜度和置信度。

## 安全边界

- 不调用重置卡兑换接口；
- 不保存 ChatGPT / Codex 登录凭据；
- 不自动发帖、发邮件或操作社交账号；
- 通知仅在概率跨过阈值或出现明确事件时触发。

