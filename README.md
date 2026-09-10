# Tibo Radar

一个运行在本机的 Codex 福利重置预测雷达。它读取公开的 Tibo / Codex
重置信号、历史事件和 OpenAI 状态事件，分别估算：

- 未来 24 / 48 小时发生全局额度重置的概率；
- 未来 24 / 48 小时普发 banked reset（重置卡）的概率；
- 两者至少发生一个的综合概率。

第一版只读公开信息，不登录 X，不读取或兑换你的 Codex 重置卡。

## 直接使用（macOS）

不需要安装第三方依赖。解压后：

1. 双击 `scripts/Tibo-Radar.command` 打开预测面板；
2. 需要系统提醒时，另行双击 `scripts/Tibo-Radar-通知.command`；
3. 关闭相应终端窗口即可停止。

若 macOS 第一次阻止 `.command` 文件，右键该文件并选择“打开”。

## 命令行使用

```bash
export PYTHONPATH="$PWD/src"
python3 -m tibo_radar snapshot
python3 -m tibo_radar serve --open
python3 -m tibo_radar watch --interval 900 --threshold 65
```

支持系统自带的 Python 3.9 及以上版本。默认每 15 分钟检查一次；只有概率
从阈值下方升到阈值上方，或出现新的明确重置事件时才通知，避免重复打扰。

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

## 运行测试

```bash
PYTHONPATH=src python3 -m unittest discover -s tests -v
```
