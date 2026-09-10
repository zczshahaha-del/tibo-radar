# 项目结构

## 数据流

```text
公开 API / 状态页
        ↓
采集与缓存
        ↓
事件归一化与去重
        ↓
AI 语义判断 ──→ 无 / 弱 / 强 / 明确预告
        ↓
历史回放质量门 ──→ 达标才附加概率区间
        ↓
快照存储 ──→ 菜单栏 / macOS 通知
```

## 模块职责

- `client.py`：下载 JSON，处理超时、重试和缓存。
- `predictor.py`：把历史基准、最新事件和状态异常组合为概率。
- `store.py`：保存最后快照和已经发过的通知。
- `notifier.py`：发送 macOS 系统通知；其他系统只打印提示。
- `server.py`：提供本地网页和 `/api/snapshot`。
- `cli.py`：提供 `snapshot`、`serve` 和 `watch` 命令。

原生 App 位于 `native/`：

- `RadarClient.swift`：并行获取公开 JSON，并写入 App 专用缓存目录。
- `AIProviderClient.swift`：调用 DeepSeek 或千问，并把结果解析为统一结构。
- `AIInputBuilder.swift`：筛选公开原文和历史基准，不采用第三方规则概率。
- `AIAnalysis.swift`：校验 AI 的语义信号、证据和时间并生成 App 快照。
- `ProbabilityCalibration.swift`：检查样本量、回测状态和基线对比；不达标就
  禁止概率进入界面。
- `APIKeyStore.swift`：只通过 macOS 钥匙串保存两家 API Key。
- `AISnapshotStore.swift`：按供应商保存最近一次成功的 AI 结果。
- `AIRefreshGate.swift`：资料变化时调用 AI；资料不变时限制后台调用频率。
- `RadarViewModel.swift`：管理首次加载、手动刷新、15 分钟刷新和状态。
- `NotificationManager.swift`：负责系统授权、强信号变化和事件去重。
- `RadarPopoverView.swift`：实现菜单栏弹出面板。
- `build-app.sh`：构建 Release 二进制并组装、临时签名 `.app`。

## 预测原则

原规则预测器只作为已否决原型保留，不再是目标架构。正式版本由 AI 阅读
每条新增证据，判断它是明确预告、强暗示、玩笑、事后描述、定向补偿还是
无关内容；再结合历史事件和反面信号给出语义信号等级。

AI 必须输出固定结构：适用范围、时间窗口、无/弱/强/明确预告、支持证据和
反面证据；禁止输出百分比。规则代码只负责采集去重、缓存、输出结构校验、
概率质量门、通知节流和故障回退，不负责理解文本含义。AI 失败时只能显示
已标记过期的上次 AI 结果，不能调用旧规则生成新概率。

DeepSeek 官方直连接口用于分析 App 采集的实时公开原文；千问除处理同一批
原文外，还通过百炼的 `enable_search` 补充联网搜索。两家接口地址固定为官方
主机，模型名称可修改，Key 分开保存在钥匙串。

概率必须来自按时间顺序隐藏未来数据的历史回放，并且回放必须包含 AI 语义
信号、至少 100 个时间窗、击败简单历史基线。任何一项不满足，App 只显示
“暂无可靠概率”。通过后也只显示范围，不显示假精确的单点数字。
