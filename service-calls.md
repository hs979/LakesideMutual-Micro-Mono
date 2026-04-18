# LakesideMutual 微服务架构 - Service Call 总表

## 1. 跨服务同步调用

### 1.1 OpenFeign 声明式 HTTP 客户端

调用方: **customer-management-backend** → 被调用方: **customer-core**

通过 `CustomerCoreClient`（`@FeignClient`）声明式接口，经 `CustomerCoreRemoteProxy` 封装后由 `CustomerInformationHolder` 控制器使用。

| # | 调用方类 | 被调用方端点 | HTTP 方法 | 描述 |
|---|---------|-------------|----------|------|
| F1 | `CustomerCoreClient.getCustomers()` | `/customers?filter=&limit=&offset=` | GET | 分页查询客户列表 |
| F2 | `CustomerCoreClient.getCustomer()` | `/customers/{ids}` | GET | 根据 ID（支持逗号分隔多个）获取客户 |
| F3 | `CustomerCoreClient.updateCustomer()` | `/customers/{customerId}` | PUT | 更新客户资料 |

认证方式：通过 `CustomerCoreClientConfiguration` 配置 `APIKeyRequestInterceptor` 添加 API Key Header。

---

### 1.2 RestTemplate 直接 HTTP 调用

#### 调用方: **customer-self-service-backend** → 被调用方: **customer-core**

通过 `CustomerCoreRemoteProxy`（使用 `RestTemplate`），带有 Resilience4j `@CircuitBreaker` 熔断保护。

| # | 调用方方法 | 被调用方端点 | HTTP 方法 | 描述 |
|---|----------|-------------|----------|------|
| R1 | `CustomerCoreRemoteProxy.getCustomer()` | `/customers/{id}` | GET | 获取单个客户信息（带熔断降级） |
| R2 | `CustomerCoreRemoteProxy.changeAddress()` | `/customers/{id}/address` | PUT | 修改客户地址 |
| R3 | `CustomerCoreRemoteProxy.createCustomer()` | `/customers` | POST | 创建新客户 |
| R4 | `CustomerCoreRemoteProxy.getCitiesForPostalCode()` | `/cities/{postalCode}` | GET | 根据邮编查询城市 |

#### 调用方: **policy-management-backend** → 被调用方: **customer-core**

通过 `CustomerCoreRemoteProxy`（使用 `RestTemplate`）。

| # | 调用方方法 | 被调用方端点 | HTTP 方法 | 描述 |
|---|----------|-------------|----------|------|
| R5 | `CustomerCoreRemoteProxy.getCustomer()` | `/customers/{id}` | GET | 获取单个客户信息 |
| R6 | `CustomerCoreRemoteProxy.getCustomers()` | `/customers?filter=&limit=&offset=` | GET | 分页查询客户列表 |
| R7 | `CustomerCoreRemoteProxy.getCustomersById()` | `/customers/{ids}` | GET | 根据 ID（支持逗号分隔多个）获取客户 |

---

### 1.3 gRPC 远程过程调用

调用方: **risk-management-client** → 被调用方: **risk-management-server**

> **注意**：`risk-management-server` 和 `risk-management-client` 已在微服务版本和单体版本中被完整删除。

| # | 调用方 | 服务定义 | 方法 | 描述 |
|---|-------|---------|------|------|
| G1 | `risk-management-client` | `RiskManagement` (gRPC service) | `Trigger(TriggerRequest) returns (stream TriggerReply)` | Server-streaming RPC，客户端发起触发请求，服务端返回进度信息流和最终 CSV 风险报告 |

---

## 2. 跨服务异步调用（ActiveMQ 消息队列）

项目使用 ActiveMQ 作为消息中间件，Broker 嵌入在 `policy-management-backend` 中（`spring.activemq.broker-url=vm://embedded?broker.persistent=false`），同时支持 TCP (JMS) 和 STOMP 协议。

Java 端使用 `JmsTemplate` 发送、`@JmsListener` 接收；Node.js 端（已删除的 `risk-management-server`）使用 `stompit` (STOMP 协议) 消费消息。

| # | 生产者 (Producer) | 消费者 (Consumer) | 队列名 | 事件类型 | 事件类 | 描述 |
|---|------------------|------------------|-------|---------|-------|------|
| M1 | `customer-self-service-backend`<br>`PolicyManagementMessageProducer` | `policy-management-backend`<br>`InsuranceQuoteRequestMessageConsumer` | `insurance-quote-request-event-queue` | `InsuranceQuoteRequestEvent` | 新保险报价请求 | 客户提交保险报价请求后，self-service 通过 JMS 通知 policy-management 创建对应报价请求 |
| M2 | `customer-self-service-backend`<br>`PolicyManagementMessageProducer` | `policy-management-backend`<br>`CustomerDecisionMessageConsumer` | `customer-decision-event-queue` | `CustomerDecisionEvent` | 客户接受/拒绝报价 | 客户对保险报价做出接受或拒绝决策后，通知 policy-management 处理 |
| M3 | `policy-management-backend`<br>`CustomerSelfServiceMessageProducer` | `customer-self-service-backend`<br>`InsuranceQuoteResponseMessageConsumer` | `insurance-quote-response-event-queue` | `InsuranceQuoteResponseEvent` | 保险报价响应 | policy-management 回复报价后，通知 self-service 更新报价请求状态 |
| M4 | `policy-management-backend`<br>`CustomerSelfServiceMessageProducer` | `customer-self-service-backend`<br>`InsuranceQuoteExpiredMessageConsumer` | `insurance-quote-expired-event-queue` | `InsuranceQuoteExpiredEvent` | 报价过期 | 由 `ExpirationCheckerJob`（Quartz 定时任务）触发，检测到报价过期后通知 self-service |
| M5 | `policy-management-backend`<br>`CustomerSelfServiceMessageProducer` | `customer-self-service-backend`<br>`PolicyCreatedMessageConsumer` | `policy-created-event-queue` | `PolicyCreatedEvent` | 保单已创建 | 客户接受报价后 policy-management 创建保单，通知 self-service 更新状态 |
| M6 | `policy-management-backend`<br>`RiskManagementMessageProducer` | `risk-management-server`<br>(STOMP subscriber) | `newpolicies` | 保单事件 (`UpdatePolicyEvent` / `DeletePolicyEvent`) | 保单事件通知风险管理 | 保单创建/更新/删除时通知风险管理服务（**已删除**） |

### ActiveMQ 消息流示意

```
M1: [self-service] --InsuranceQuoteRequestEvent--> [insurance-quote-request-event-queue] --> [policy-management]
M2: [self-service] --CustomerDecisionEvent-------> [customer-decision-event-queue]       --> [policy-management]
M3: [policy-management] --InsuranceQuoteResponseEvent--> [insurance-quote-response-event-queue] --> [self-service]
M4: [policy-management] --InsuranceQuoteExpiredEvent---> [insurance-quote-expired-event-queue]  --> [self-service]
M5: [policy-management] --PolicyCreatedEvent-----------> [policy-created-event-queue]           --> [self-service]
M6: [policy-management] --UpdatePolicyEvent/DeletePolicyEvent--> [newpolicies] --> [risk-management-server] (已删除)
```

---

## 3. 前端 → 后端 HTTP 调用（浏览器 fetch）

前端通过浏览器原生 `fetch` API 调用后端 REST API（BFF 模式）。

### 3.1 customer-management-frontend

目标后端通过环境变量 `REACT_APP_CUSTOMER_MANAGEMENT_BACKEND`（默认 `http://localhost:8100`）和 `REACT_APP_CUSTOMER_SELF_SERVICE_BACKEND`（默认 `http://localhost:8080`）配置。使用 `redux-rest-easy` 库封装。

| # | 前端模块 | 目标后端 | HTTP 方法 | 端点 | 描述 |
|---|--------|---------|----------|------|------|
| FE1 | `customers.js` | customer-management-backend | GET | `/customers?filter=&limit=&offset=` | 分页查询客户列表 |
| FE2 | `customers.js` | customer-management-backend | GET | `/customers/{customerId}` | 获取单个客户详情 |
| FE3 | `customers.js` | customer-management-backend | PUT | `/customers/{customerId}` | 更新客户资料 |
| FE4 | `customers.js` | customer-self-service-backend | POST | `/customers` | 创建新客户（带 JWT Token） |
| FE5 | `users.js` | customer-self-service-backend | POST | `/auth/signup` | 注册新用户 |
| FE6 | `users.js` | customer-self-service-backend | POST | `/auth` | 用户登录获取 Token |
| FE7 | `interactionlogs.js` | customer-management-backend | GET | `/interaction-logs/{customerId}` | 获取客户交互日志 |
| FE8 | `interactionlogs.js` | customer-management-backend | PATCH | `/interaction-logs/{customerId}` | 确认已读交互 |
| FE9 | `notifications.js` | customer-management-backend | GET | `/notifications` | 获取通知列表 |
| FE10 | `ChatView.js` | customer-management-backend | WebSocket | `/ws` (SockJS + STOMP) | 实时聊天消息收发 |
| FE11 | `Notifications.js` | customer-management-backend | WebSocket | `/ws` (SockJS + STOMP) | 实时通知推送 |

### 3.2 customer-self-service-frontend

目标后端通过环境变量 `REACT_APP_CUSTOMER_SELF_SERVICE_BACKEND`（默认 `http://localhost:8080`）、`REACT_APP_POLICY_MANAGEMENT_BACKEND` 和 `REACT_APP_CUSTOMER_MANAGEMENT_BACKEND` 配置。

| # | 前端 API 模块 | 目标后端 | HTTP 方法 | 端点 | 描述 |
|---|-------------|---------|----------|------|------|
| FE12 | `customerselfservice.js` | customer-self-service-backend | POST | `/auth` | 用户登录 |
| FE13 | `customerselfservice.js` | customer-self-service-backend | POST | `/auth/signup` | 用户注册 |
| FE14 | `customerselfservice.js` | customer-self-service-backend | GET | `/user` | 获取当前用户信息 |
| FE15 | `customerselfservice.js` | customer-self-service-backend | GET | `/customers/{customerId}` | 获取客户信息 |
| FE16 | `customerselfservice.js` | customer-self-service-backend | POST | `/customers` | 完成注册（补充个人信息） |
| FE17 | `customerselfservice.js` | customer-self-service-backend | PUT | `{customer._links["address.change"].href}` | 修改客户地址（HATEOAS 链接） |
| FE18 | `customerselfservice.js` | customer-self-service-backend | GET | `/cities/{postalCode}` | 根据邮编查询城市 |
| FE19 | `customerselfservice.js` | customer-self-service-backend | POST | `/insurance-quote-requests` | 提交保险报价请求 |
| FE20 | `customerselfservice.js` | customer-self-service-backend | GET | `/customers/{customerId}/insurance-quote-requests` | 获取客户的保险报价请求列表 |
| FE21 | `customerselfservice.js` | customer-self-service-backend | GET | `/insurance-quote-requests/{id}` | 获取单个保险报价请求 |
| FE22 | `customerselfservice.js` | customer-self-service-backend | PATCH | `/insurance-quote-requests/{id}` | 客户接受/拒绝保险报价 |
| FE23 | `policymanagement.js` | policy-management-backend | GET | `/customers/{customerId}/policies` | 获取客户的保单列表 |
| FE24 | `customermanagement.js` | customer-management-backend | GET | `/interaction-logs/{customerId}` | 获取交互日志 |

### 3.3 policy-management-frontend

目标后端通过环境变量 `VUE_APP_POLICY_MANAGEMENT_BACKEND`（默认 `http://localhost:8090`）配置。Vue.js 应用。

| # | 前端 API 函数 | 目标后端 | HTTP 方法 | 端点 | 描述 |
|---|-------------|---------|----------|------|------|
| FE25 | `getCustomers()` | policy-management-backend | GET | `/customers?filter=` | 查询客户列表 |
| FE26 | `getCustomer()` | policy-management-backend | GET | `/customers/{customerId}` | 获取单个客户 |
| FE27 | `getInsuranceQuoteRequests()` | policy-management-backend | GET | `/insurance-quote-requests` | 获取所有保险报价请求 |
| FE28 | `getInsuranceQuoteRequest()` | policy-management-backend | GET | `/insurance-quote-requests/{id}` | 获取单个保险报价请求 |
| FE29 | `respondToInsuranceQuoteRequest()` | policy-management-backend | PATCH | `/insurance-quote-requests/{id}` | 回复保险报价（接受/拒绝） |
| FE30 | `getPolicies()` | policy-management-backend | GET | `/policies?expand=customer` | 获取保单列表（含客户信息展开） |
| FE31 | `getPolicy()` | policy-management-backend | GET | `/policies/{policyId}` | 获取单个保单 |
| FE32 | `getCustomerPolicies()` | policy-management-backend | GET | `/customers/{customerId}/policies` | 获取客户的保单列表 |
| FE33 | `createPolicy()` | policy-management-backend | POST | `/policies` | 创建新保单 |
| FE34 | `updatePolicy()` | policy-management-backend | PUT | `/policies/{policyId}` | 更新保单 |
| FE35 | `deletePolicy()` | policy-management-backend | DELETE | `/policies/{policyId}` | 删除保单 |
| FE36 | `computeRiskFactor()` | policy-management-backend | POST | `/riskfactor/compute` | 计算风险因子 |

---

## 4. 汇总统计

| 调用类型 | 数量 | 说明 |
|---------|------|------|
| OpenFeign (同步) | 3 | customer-management → customer-core |
| RestTemplate (同步) | 7 | self-service → core (4), policy → core (3) |
| gRPC (同步) | 1 | risk-management-client → risk-management-server（已删除） |
| ActiveMQ/JMS (异步) | 6 | self-service ↔ policy (5), policy → risk-management (1，已删除) |
| 前端 HTTP (browser fetch) | 36 | 含 2 个 WebSocket 连接 |
| **总计** | **53** | |

---

## 5. 服务间调用关系图

```
                              ┌──────────────────────┐
                              │   customer-core      │
                              │   (port 8110)        │
                              └──────────┬───────────┘
                                   ▲  ▲  ▲
                 Feign (F1-F3)─────┘  │  └─── RestTemplate (R5-R7)
                                      │
              RestTemplate (R1-R4)────┘
                                      
    ┌─────────────────────┐                     ┌─────────────────────────┐
    │  customer-management│                     │  customer-self-service  │
    │  -backend           │                     │  -backend               │
    │  (port 8100)        │                     │  (port 8080)            │
    └─────────────────────┘                     └────────────┬────────────┘
                                                        │         ▲
                                           JMS (M1,M2)  │         │  JMS (M3,M4,M5)
                                                        ▼         │
                                                ┌─────────────────────────┐
                                                │  policy-management      │
                                                │  -backend               │
                                                │  (port 8090)            │
                                                │  [embedded ActiveMQ]    │
                                                └─────────────┬───────────┘
                                                              │
                                                  JMS/STOMP (M6, 已删除)
                                                              │
                                                              ▼
                                                ┌─────────────────────────┐
                                                │  risk-management-server │
                                                │  (Node.js, 已删除)      │
                                                └─────────────────────────┘
                                                              ▲
                                                    gRPC (G1, 已删除)
                                                              │
                                                ┌─────────────────────────┐
                                                │  risk-management-client │
                                                │  (Node.js, 已删除)      │
                                                └─────────────────────────┘

前端调用:
    customer-management-frontend  ──HTTP──►  customer-management-backend (FE1-FE9)
                                  ──WS────►  customer-management-backend (FE10-FE11)
                                  ──HTTP──►  customer-self-service-backend (FE4-FE6)

    customer-self-service-frontend ──HTTP──►  customer-self-service-backend (FE12-FE22)
                                   ──HTTP──►  policy-management-backend (FE23)
                                   ──HTTP──►  customer-management-backend (FE24)

    policy-management-frontend     ──HTTP──►  policy-management-backend (FE25-FE36)
```
