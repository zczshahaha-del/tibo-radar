# macOS App 使用与维护

## 支持范围

- 系统：macOS 13 及以上。
- 当前验收包：Apple Silicon（arm64）。
- 签名：本机临时签名，不是 Developer ID 公证版本。

## 安装

1. 解压交付的 zip。
2. 把 `Tibo Radar.app` 拖入“应用程序”文件夹。
3. 双击启动；首次启动时按系统提示允许通知。
4. 如果系统阻止临时签名 App，右键 App，选择“打开”。

启动后不会显示普通窗口或 Dock 图标。右上角菜单栏出现雷达图标，点击即可
展开预测面板。

## 升级

退出旧版，用新版 `Tibo Radar.app` 替换“应用程序”中的旧文件，再重新启动。
公开数据缓存和通知去重状态保存在 App 外，因此升级不会清空它们。

## 卸载

1. 从菜单栏面板底部退出 App。
2. 把 `Tibo Radar.app` 移到废纸篓。

这会保留公开数据缓存。如需完全清理，再删除：

```text
~/Library/Application Support/TiboRadar
```

系统通知权限可在“系统设置 → 通知”中单独修改。

## 本地数据和权限

- App 只申请系统通知权限。
- 缓存目录只包含公开 API 返回内容。
- 通知去重状态由 macOS `UserDefaults` 保存。
- App 不保存 ChatGPT、Codex 或 X 的账号和凭据。

## 构建

```bash
swift test --package-path native
native/build-app.sh
```

打包脚本会生成 Release 二进制、`.icns` 图标、标准 App 目录并执行本机临时
签名。若以后公开分发，需要另行配置 Developer ID、公证和通用架构构建。
