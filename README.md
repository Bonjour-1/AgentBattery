# AgentBattery

AgentBattery 是一款面向 Windows 的多服务商 AI 账户看板，用于集中查看余额、用量与连接状态，并提供服务商管理、自动刷新和个性化主题。

## 功能概览

- 多服务商余额、今日用量与本月用量统一展示
- 手动刷新与自动刷新
- 添加、编辑、启用、排序、导入和删除服务商
- 支持 OpenAI 兼容 API 服务商
- 支持从 Hermes 导入服务商配置
- 支持通用网页账单与浏览器 cURL 导入
- API Key、Cookie、Token 等敏感信息使用 Windows 安全存储保存
- 内置主题与自定义主题工作台
- 自定义背景、渐变、液态玻璃卡片与主题包导入/导出
- Windows 托盘与窗口布局支持

## 使用说明

开始使用前，请阅读以下说明：

- [通用网页账单配置说明](docs/通用网页账单配置说明.md)：余额、今日/本月用量、cURL 导入、安全变量与常见问题。

使用网页账单时，务必先阅读配置说明。不要在聊天、截图、Issue 或普通配置字段中泄露 API Key、Cookie、Authorization / Bearer Token 等敏感信息。

## 快速开始

1. 启动 AgentBattery。
2. 打开「管理服务商」。
3. 添加或编辑服务商，填写名称、Base URL 与 API Key。
4. 保存后回到主页，点击刷新查看状态。

如果服务商需要从网页控制台获取余额或用量，请按 [通用网页账单配置说明](docs/通用网页账单配置说明.md) 配置。

## 开发

### 环境

- Flutter / Dart：Dart SDK `^3.12.2`
- 平台：Windows 桌面端

### 获取依赖

```powershell
flutter pub get
```

### 运行 Debug 版

```powershell
flutter run -d windows
```

### 测试与静态分析

```powershell
flutter test
flutter analyze
```

### 构建 Release 版

```powershell
flutter build windows --release
```

构建输出位于：

```text
build\windows\x64\runner\Release\
```

## 项目结构

```text
lib/
  models/       数据模型
  services/     网络请求、安全存储、配置持久化、主题服务
  state/        应用状态与刷新逻辑
  ui/           页面、组件、主题与窗口布局

test/           单元测试与 Widget 测试
docs/           使用文档
```

## 安全说明

- 敏感凭据保存在 Windows 安全存储中，不写入普通配置 JSON。
- 从浏览器复制 cURL 时，内容可能包含 Cookie 或 Token；导入后请妥善处理剪贴板内容。
- 若网页账单请求返回 401 / 403，通常需要在服务商网页重新获取有效凭据。

## 许可证

请以仓库中的许可证文件和发布说明为准。
