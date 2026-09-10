# Tibo Radar

一个运行在本机的 Codex 福利重置预测雷达。它读取公开的 Tibo / Codex
重置信号、历史事件和 OpenAI 状态事件，分别估算：

- 未来 24 / 48 小时发生全局额度重置的概率；
- 未来 24 / 48 小时普发 banked reset（重置卡）的概率；
- 两者至少发生一个的综合概率。

原生 App 只读公开信息，不登录 X，不读取或兑换你的 Codex 重置卡。

## 使用原生 macOS App

当前验收包支持 Apple Silicon Mac 和 macOS 13 及以上版本，不需要 Python、
浏览器或终端：

1. 解压 `Tibo-Radar-v0.2.0-macOS-arm64.zip`；
2. 把 `Tibo Radar.app` 拖入“应用程序”，或直接双击运行；
3. 第一次打开时允许系统通知；
4. 点击屏幕右上角的雷达图标查看预测，点击面板底部的退出按钮即可停止。

当前是本机验收包，使用临时签名。如果 macOS 第一次阻止打开，请右键
`Tibo Radar.app` 并选择“打开”。安装、升级和卸载说明见
[`docs/macos-app.md`](docs/macos-app.md)。

## 原生 App 怎样工作

- 启动后只常驻菜单栏，不显示 Dock 图标；
- 首次启动立即读取信号，此后每 15 分钟刷新，也可以手动刷新；
- 24 小时综合概率从 65% 以下升到 65% 以上时发送系统通知；
- 出现新的明确重置或重置卡事件时提醒一次，不重复轰炸；
- 网络失败时读取 `Application Support/TiboRadar` 中的最近公开缓存。

## 构建和测试

```bash
swift test --package-path native
TIBO_RADAR_LIVE_TEST=1 swift test --package-path native
native/build-app.sh
```

Release App 输出到 `dist/native/Tibo Radar.app`。SwiftUI 源码、测试、图标
生成和打包脚本均位于 `native/`。

## Python 原型

`src/tibo_radar/` 保留了最初用于验证预测规则的 Python 原型。它不参与原生
App 运行；需要回归对照时可按下面方式执行：

```bash
PYTHONPATH=src python3 -m tibo_radar snapshot
PYTHONPATH=src python3 -m unittest discover -s tests -v
```

## 数据来源

- `codex-reset.com` 提供的公开 forecast、timeline 与 feed API；
- OpenAI Status 的公开状态数据；
- 原始 Tibo 帖子的公开链接，用于展示证据。

第三方数据可能延迟或中断，因此每次预测都会显示数据新鲜度和置信度。

## 概率应该怎么读

- “全局重置”是直接恢复大范围用户额度；
- “普发重置卡”是发到账户、可在以后手动使用的 banked reset；
- “故障补发”是条件概率，只适用于明确故障时段内受影响的用户；
- “综合概率”表示前两种普惠事件至少发生一种，不包含定向补发。

这是一项小样本预测，只适合帮助安排用量，不是 OpenAI 的承诺。

## 安全边界

- 不调用重置卡兑换接口；
- 不保存 ChatGPT / Codex 登录凭据；
- 不自动发帖、发邮件或操作社交账号；
- 通知仅在概率跨过阈值或出现明确事件时触发。
