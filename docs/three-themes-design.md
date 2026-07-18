# Flutter 三主题设计

## 目标

在现有 Flutter AgentBattery 的 MIKU Material 3 主题基础上，新增“极简玻璃”和“可爱风”。主题切换应影响主页、服务商卡、指标卡、服务商管理页、编辑弹窗、按钮、状态色和背景，而非仅切换背景。

## 主题

### MIKU

保留当前深青→MIKU 青绿→冰青舞台渐变与克制粉色 Spotlight。作为默认主题。

### 极简玻璃

- 冰蓝白背景与淡紫蓝光晕
- 白色半透明表面感（Flutter 使用不透明近似色与渐变层，避免依赖额外模糊插件）
- 细边框、低对比阴影、大留白
- 主色 #6D7CFF，辅助色 #4BC9AE
- 不使用可爱装饰或高饱和点缀

### 可爱风

- 桃粉 #FF8FAB、浅粉 #FFE2EC、奶白底
- 大圆角、柔和粉色渐变和心形/星点小装饰
- Filled / tonal / outlined 按钮保持清晰层级
- 颜色状态仍保证错误与连接状态可辨识

## 实现边界

- 新建集中 ThemeTokens / ThemeMode 配置，而不是在页面内散落颜色。
- 主题选项由当前 MIKU/其他改为 MIKU/玻璃/可爱风，选择持久化进 AppSnapshot。
- 保留动态服务商配置、Key 安全逻辑、API/余额逻辑，主题改动不触碰这些逻辑。

## 验证

- 增加主题序列化/反序列化与三个主题可选的单元测试。
- Widget 测试覆盖三个主题下主页可渲染且无 overflow。
- `flutter test`、`flutter analyze`、`flutter build windows --debug` 必须通过。
