# Tibo Radar

一个运行在本机的 Codex 福利重置信号雷达。它读取公开的 Tibo / Codex
动态、历史事件和 OpenAI 状态事件，分别判断：

- 有没有面向未来的全局额度重置信号；
- 有没有普发 banked reset（重置卡）信号；
- 有没有只针对故障用户的补发，以及现在是否值得加速使用额度。

原生 App 只读公开信息，不登录 X，不读取或兑换你的 Codex 重置卡。DeepSeek
或千问负责理解原文，但不能自行生成百分比。概率只有通过历史回放和质量门后
才会以区间显示；当前回测未达标，所以 App 会诚实显示“暂无可靠概率”。

## 使用原生 macOS App

当前验收包支持 Apple Silicon Mac 和 macOS 13 及以上版本，不需要 Python、
浏览器或终端：

1. 解压 `Tibo-Radar-v0.4.0-macOS-arm64.zip`；
2. 把 `Tibo Radar.app` 拖入“应用程序”，或直接双击运行；
3. 点击菜单栏雷达图标，再点右上角齿轮；
4. 选择 DeepSeek 或千问，填写自己的 API Key，点击“保存并测试”；
5. 返回面板并点击刷新；第一次产生有效 AI 结果后再按提示允许系统通知。

当前是本机验收包，使用临时签名。如果 macOS 第一次阻止打开，请右键
`Tibo Radar.app` 并选择“打开”。安装、升级和卸载说明见
[`docs/macos-app.md`](docs/macos-app.md)。

## 原生 App 怎样工作

- 启动后只常驻菜单栏，不显示 Dock 图标；
- 每 15 分钟检查公开信号；发现新资料时调用 AI，相同资料最多每小时重新判断
  一次，避免无意义消耗额度；手动刷新始终立即调用 AI；
- DeepSeek 分析 App 实时采集的公开原文；千问还会开启百炼联网搜索；
- 两家使用独立 Key，可以随时切换，并可以修改模型名称；
- AI 判断从无/弱信号升为强信号或明确预告时发送系统通知；
- 出现新的明确重置或重置卡事件时提醒一次，不重复轰炸；
- 网络或 AI 失败时读取 `Application Support/TiboRadar` 中的最近 AI 快照，并
  明确标记为旧结果；绝不回退到规则概率。

## API Key

- DeepSeek 默认模型：`deepseek-flash`，使用 DeepSeek 官方接口。
- 千问默认模型：`qwen-plus`，使用阿里云百炼中国站接口并开启联网搜索。
- API Key 只保存在 macOS 钥匙串；不会写入 UserDefaults、缓存、日志或交付包。
- App 不提供自定义接口地址，避免误把 Key 发给非官方主机。
- 刷新会产生模型调用费用，具体费用由对应服务商账户结算。

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

- `codex-reset.com` 提供的公开历史、timeline 与 Tibo feed API；其中的概率只有
  在回测明确包含 AI 信号并通过质量门后，才可能作为区间显示；
- OpenAI Status 的公开状态数据；
- 原始 Tibo 帖子的公开链接，用于展示证据。
- 选择千问时，由阿里云百炼提供的联网搜索补充近期网络讨论。

第三方数据可能延迟或中断，因此每次判断都会显示数据新鲜度和具体原因。

## 结果应该怎么读

- “全局重置”是直接恢复大范围用户额度；
- “普发重置卡”是发到账户、可在以后手动使用的 banked reset；
- “故障补发”只适用于明确故障时段内受影响的用户；
- “没有新信号 / 有一点迹象 / 值得关注 / 已有明确预告”由 AI 阅读原文后
  判断，不是数字概率；
- “最可能什么时候”是 AI 对发生时间的估计；证据不足时直接显示“暂时算不出”。
- “暂无可靠概率”表示历史回放还不够准，App 拒绝展示模型随口给出的数字。
- 将来只有包含 AI 语义信号、样本量达标并击败简单基线的回放结果，才能显示
  概率范围；不会再显示未经校准的单点百分比。

这是一项小样本预测，只适合帮助安排用量，不是 OpenAI 的承诺。

## 安全边界

- 不调用重置卡兑换接口；
- DeepSeek / 千问 API Key 只保存到 macOS 钥匙串；
- 不保存 ChatGPT / Codex 登录凭据；
- 不自动发帖、发邮件或操作社交账号；
- 通知仅在出现新强信号、明确预告或新确认事件时触发。
