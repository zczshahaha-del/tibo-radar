# 项目结构

## 数据流

```text
公开 API / 状态页
        ↓
采集与缓存
        ↓
事件归一化与去重
        ↓
历史回放范围 ──→ AI 的预测基准
        ↓
AI 综合历史与近期证据 ──→ 全局 / 普发卡 / 综合 24/48 小时范围
        ↓
范围关系校验 ──→ 拒绝全零、非法或前后矛盾的结果
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

- `RadarClient.swift`：并行获取公开 JSON、补全回复上下文，并写入 App 专用缓存目录。
- `ReplyContextClient.swift`：按公开帖子 ID 尽力获取父帖和引用帖正文；失败时不影响
  主 feed，并允许沿用已有缓存。
- `AIProviderClient.swift`：调用 DeepSeek 或千问，并把结果解析为统一结构。
- `AIInputBuilder.swift`：筛选公开原文，并把历史回放概率作为 AI 预测基准。
- `AIAnalysis.swift`：校验 AI 概率范围、证据和时间关系并生成 App 快照。
- `ProbabilityCalibration.swift`：检查历史基准的样本量、范围和基线对比。
- `APIKeyStore.swift`：只通过 macOS 钥匙串保存两家 API Key。
- `AISnapshotStore.swift`：按供应商保存最近一次成功的 AI 结果。
- `AIRefreshGate.swift`：资料变化时调用 AI；资料不变时限制后台调用频率。
- `RadarViewModel.swift`：管理首次加载、手动刷新、2 小时自动刷新和状态。
- `NotificationManager.swift`：负责系统授权、AI 概率阈值和事件去重。
- `TiboRadarApp.swift`：以纯 AppKit accessory 应用创建 `NSStatusItem` 和
  `NSPopover`，不声明独立设置窗口，并明确控制弹窗尺寸。
- `RadarPopoverView.swift`：实现菜单栏弹出面板并请求收起、展开所需高度。
- `build-app.sh`：构建 Release 二进制并组装、临时签名 `.app`。

## 预测原则

原规则预测器只作为已否决原型保留，不再是目标架构。正式版本由 AI 阅读
历史概率基准和每条新增证据，判断它是明确预告、强暗示、玩笑、事后描述、
定向补偿还是无关内容，再给出全局、普发卡和综合事件的 24/48 小时概率范围。

AI 必须输出固定结构：每个预测的低值、最可能值和高值，以及时间窗口、行动
建议、支持证据和反面证据。没有新动态也必须在历史基准附近作出预测，不能
返回全零或“无预测”。规则代码只负责采集去重、缓存、结构和数学关系校验、
通知节流和故障回退，不负责理解文本含义。AI 失败时只能显示已标记过期的
上次 AI 结果，不能调用旧规则生成新概率。

DeepSeek 官方直连接口用于分析 App 采集的实时公开原文；千问除处理同一批
原文外，还通过百炼的 `enable_search` 补充联网搜索。两家接口地址固定为官方
主机，模型名称可修改，Key 分开保存在钥匙串。

Tibo 回复的父帖和引用帖由 `api.fxtwitter.com` 按公开帖子 ID 尽力补全，不传账号、
Cookie 或私有数据。补全失败时 AI 会收到上下文缺失标记，不能猜测代词或日期指向。

历史基准必须来自按时间顺序隐藏未来数据的回放；至少 100 个时间窗、范围
合法且击败简单猜测后才会交给 AI。AI 结合该基准与当前证据给出最终范围，
程序要求所有普发预测非零、48 小时累计概率不低于 24 小时，综合事件概率不
低于任一分类。界面只显示范围，不把最可能值包装成假精确的单点结论。
