# 项目结构

## 数据流

```text
公开 API / 状态页
        ↓
采集与缓存
        ↓
事件归一化与去重
        ↓
概率引擎 ──→ 解释与置信区间
        ↓
快照存储 ──→ 网页 / 命令行 / macOS 通知
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
- `Predictor.swift`：移植经过测试的可解释概率规则。
- `RadarViewModel.swift`：管理首次加载、手动刷新、15 分钟刷新和状态。
- `NotificationManager.swift`：负责系统授权、跨阈值判断和事件去重。
- `RadarPopoverView.swift`：实现菜单栏弹出面板。
- `build-app.sh`：构建 Release 二进制并组装、临时签名 `.app`。

## 预测原则

第一版使用可解释规则，并参考公开预测 API 的历史基准。重置卡与全局重置
分别计算，最后再计算联合概率。每个修正项都必须出现在输出证据中。

数据不新鲜、事件范围不明确或样本不足时，降低置信度，而不是给出看起来
很精确的结论。
