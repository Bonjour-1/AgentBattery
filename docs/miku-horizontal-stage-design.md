# MIKU 横向舞台布局设计

## 目标

保留玻璃和可爱风的紧凑桌面使用体验；仅在切换到 MIKU 时，把 AgentBattery 调整为横向演唱会舞台布局，以匹配右侧人物背景图的 16:9 构图，并确保数据不被人物遮挡。

## 窗口规则

### MIKU

- 进入 MIKU：窗口目标尺寸 `1320 × 760`，最小尺寸 `1080 × 680`。
- 左侧约 55% 为标题、概览、服务商卡与操作区。
- 右侧约 45% 展示 `assets/images/miku_stage_background.png` 中的人物、舞台灯光与音符。
- 左侧叠加深青到半透明青绿遮罩；数据卡使用冰青白半透明材质，保障可读性。
- 当可用窗口宽度低于约 920px 时，仍保持功能完整：卡片变为纵向流；背景人物降低透明度并向右裁切，优先保证文字与按钮。

### 玻璃、可爱风

- 维持现有紧凑窗口目标尺寸 `680 × 800` 与最小尺寸 `620 × 720`。
- 切离 MIKU 后恢复这组尺寸，不保留 MIKU 的横向强制比例。

## 主题切换数据流

1. 用户从主题菜单选择 MIKU / 玻璃 / 可爱风。
2. `BatteryController.selectTheme` 持久化主题，并通知 UI。
3. 根应用监听主题变化：
   - MIKU：经 `window_manager` 调整窗口 size/minimumSize；
   - 玻璃/可爱风：恢复紧凑 size/minimumSize。
4. `HomeScreen` 根据主题切换布局：MIKU 以左右舞台 Stack/Row 布局；其他主题沿用现有纵向头部 + 内容区布局。

## 资源

- 登记 Flutter asset：`assets/images/miku_stage_background.png`。
- 不生成第二张图；先使用已验收的右对齐 MIKU 舞台背景。

## 安全与兼容

- 不触碰动态服务商、余额 API、Key、本地存储、托盘或单实例逻辑。
- `window_manager` 调整尺寸在非 Windows / Widget 测试环境下跳过或通过注入隔离。
- 背景图加载失败时退回现有 MIKU 渐变，程序可正常启动。

## 验证

- 测试 MIKU / 玻璃 / 可爱主题切换对应的 layout marker 与窗口配置选择。
- Widget 测试覆盖 MIKU 横向宽窗口和窄窗口，不产生 overflow。
- `flutter test`、`flutter analyze`、`flutter build windows --debug`。
- Windows 运行后以实际窗口截图验收：MIKU 人物处于右侧，左侧数据不被遮挡；玻璃与可爱风切回紧凑窗口。
