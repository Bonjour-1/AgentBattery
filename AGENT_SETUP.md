# 给 Agent 的网页账单接入说明

这份文件给用户自己的 Agent 阅读。目标不是让 Agent 登录或控制 AgentBattery，而是调查供应商的账单接口，生成一份不含凭据的交接文件，再由用户在 AgentBattery 界面中完成配置和安全变量录入。

当前版本只支持三类数值：余额 `balance`、今日用量 `daily`、本月用量 `monthly`。套餐、订阅状态、配额和重置时间暂时不要写进交接文件。

## 安全红线

真实的 API Key、Cookie、Access Token、Refresh Token、Bearer Token 都是 Secret。

不要把 Secret 放进：

- 交接 JSON、Git、Issue；
- 聊天回复、截图、普通日志；
- URL、JSON Path、数据处理表达式；
- 命令参数或 shell 历史。

请求模板只能写变量引用，例如：

```json
{
  "Authorization": "Bearer ${BILLING_TOKEN}",
  "Cookie": "${BILLING_COOKIE}"
}
```

不要在最终回复中复述请求头、Cookie 或凭据内容。只报告认证类型和验证状态。

## 调查顺序

按稳定性从高到低选择数据源：

1. 供应商公开账单 API；
2. 供应商官方 CLI 或官方 API；
3. 网页后台使用的 JSON 接口；
4. 最后才考虑解析网页 HTML。

优先找一次请求就能返回所需字段的接口。删除无关的浏览器指纹请求头。不要猜 Refresh Token 接口，也不要把短期网页 Cookie 说成可自动续期。

## 操作流程

### 1. 先确认目标

询问用户需要余额、今日用量、本月用量中的哪些项。至少配置一项。

### 2. 找到真实请求

如果没有公开接口，在用户已登录的浏览器中打开开发者工具：

1. 进入供应商账单页；
2. 打开 Network，刷新页面；
3. 找返回 JSON 的请求；
4. 在 Response 中确认目标数值；
5. 记录方法、URL、必要的请求头/查询参数/请求体和字段路径。

不要要求用户把完整 cURL 或 Cookie 发进聊天。需要读取浏览器会话时，应在用户本机受控环境内处理，并且不回显值。

### 3. 判断凭据类型

- 长期 API Key：通常可作为 `static secret`；
- 网页 Bearer Token、Cookie：默认标记为 `manual session`；
- 只有确认了供应商公开、合法的刷新流程，才能声明支持自动续期。

第一期 AgentBattery 不会自动续期网页登录凭据。

### 4. 生成交接文件

遵循：

- Schema：`schemas/provider-billing-agent-handoff.schema.json`
- 示例：`examples/agent-handoff.example.json`

文件中只写请求规则、解析规则和 Secret 的名称/类型，不写 Secret 值。敏感位置必须使用已声明的 `${VARIABLE_NAME}`。

### 5. 本地校验

在仓库根目录执行：

```powershell
dart run tools/validate_agent_handoff.dart path\to\handoff.json
```

成功会输出 `VALID`。失败诊断只包含字段路径和错误类型，不会回显请求值。

这个工具目前只负责校验，不会把配置或凭据写进 AgentBattery。

### 6. 交给用户应用

当前应用方式：

1. 用户打开 AgentBattery 的“管理服务商”；
2. 按交接文件填写通用网页账单请求和数据处理规则，或在对应指标中使用“Copy as cURL (bash)”导入；
3. 真实 Token/Cookie 只填入 AgentBattery 的“安全变量”；
4. 保存后刷新，确认目标数值可读取。

不要直接修改 AgentBattery 的内部存储文件。

## 凭据过期后的修复

出现 401/403 时，只更新凭据，不要重做 URL、请求模板和解析规则。

`renew_credentials` 交接任务应满足：

- `required_variables` 只列出需要更新的变量名；
- `preserve_billing_rules` 必须为 `true`；
- 不包含任何旧值或新值；
- 用户在 AgentBattery 的安全变量中替换对应凭据；
- 新凭据验证成功后，旧凭据才算完成替换。

如果凭据来自网页登录，最终报告应明确写“手动会话，需要重新登录”，不能承诺自动续期。

## 最终报告格式

最终只报告：

```text
供应商：<名称>
数据源：公开 API / 官方 API / 网页 JSON
已配置指标：余额 / 今日用量 / 本月用量
认证方式：长期 API Key / 网页 Bearer / 网页 Cookie
自动续期：支持 / 不支持（需要重新登录）
配置校验：通过 / 未通过
运行验证：通过 / 未执行 / 失败
```

不要附带请求头、Cookie、Token、完整 cURL 或含敏感查询参数的 URL。
