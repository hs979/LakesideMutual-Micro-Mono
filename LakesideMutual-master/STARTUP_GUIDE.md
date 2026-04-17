# LakeSide Mutual — 完整启动与测试指南

## 一、环境要求确认

| 工具 | 要求版本 | 检测命令 |
|------|---------|----------|
| Java (JDK) | 17+（已将 pom.xml 从 21 改为 17） | `java -version` |
| Maven | 3.6+ | `mvn -version` |
| Node.js | 12+（当前 v22 ✓） | `node --version` |
| npm | 6+（当前 10.9 ✓） | `npm --version` |

> 已自动修改所有 5 个 `pom.xml`，将 `<java.version>21</java.version>` 改为 `<java.version>17</java.version>`，无需安装 Java 21。

---

## 二、架构总览

```
┌─────────────────────────────────────────────────────────────────┐
│  前端层                                                          │
│  customer-self-service-frontend  :3000  (React)                 │
│  policy-management-frontend      :3010  (Vue 2)                 │
│  customer-management-frontend    :3020  (React+Redux)           │
└─────────────────┬───────────────────────────────────────────────┘
                  │ HTTP
┌─────────────────▼───────────────────────────────────────────────┐
│  后端服务层                                                       │
│  customer-self-service-backend   :8080  (Spring Boot)           │
│  policy-management-backend       :8090  (Spring Boot + ActiveMQ)│
│  customer-management-backend     :8100  (Spring Boot + WebSocket)│
│  customer-core                   :8110  (Spring Boot, 基础数据)  │
│  spring-boot-admin               :9000  (监控中心)               │
└─────────────────────────────────────────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────────────────────┐
│  消息队列 & gRPC                                                  │
│  policy-management-backend       :61613 (ActiveMQ STOMP)        │
│  policy-management-backend       :61616 (ActiveMQ TCP)          │
│  risk-management-server          :50051 (gRPC, Node.js)         │
└─────────────────────────────────────────────────────────────────┘
```

**依赖启动顺序**（必须按此顺序）：
1. `spring-boot-admin` → 无依赖
2. `customer-core` → 无依赖
3. `policy-management-backend` → 依赖 customer-core
4. `customer-management-backend` → 依赖 customer-core
5. `customer-self-service-backend` → 依赖 customer-core + policy-management-backend（ActiveMQ）
6. `risk-management-server` → 依赖 policy-management-backend（ActiveMQ）
7. 三个前端 → 依赖各自后端

---

## 三、Maven 编译与单元测试（所有后端）

> 每个服务单独编译，在 `LakesideMutual-master\` 目录下运行。

```powershell
# 进入项目根目录
cd d:\AAAresearch\microservices\LakeSideMutual-Micro-Mono\LakesideMutual-master

# 逐个编译并测试（跳过测试用 -DskipTests）
cd spring-boot-admin          ; mvn clean package ; cd ..
cd customer-core              ; mvn clean package ; cd ..
cd customer-management-backend; mvn clean package ; cd ..
cd customer-self-service-backend ; mvn clean package ; cd ..
cd policy-management-backend  ; mvn clean package ; cd ..
```

**只运行测试（不打包）**：
```powershell
cd customer-core              ; mvn test ; cd ..
cd customer-management-backend; mvn test ; cd ..
cd customer-self-service-backend ; mvn test ; cd ..
cd policy-management-backend  ; mvn test ; cd ..
```

各服务测试文件一览：

| 服务 | 测试类 | 说明 |
|------|--------|------|
| customer-core | `CustomerInformationHolderTests` | MockMvc 测试 POST/GET/PUT /customers |
| customer-core | `ArchitectureTests` | ArchUnit 分层架构验证 |
| customer-core | `CustomerAggregateRootTests` | 领域对象单元测试 |
| customer-core | `CustomerFactoryTests` | 工厂方法 + 电话验证 |
| customer-core | `AddressDtoTests` | Jackson 序列化测试 |
| customer-management-backend | `ArchitectureTests` | ArchUnit 验证 |
| customer-self-service-backend | `AuthenticationControllerTests` | 注册接口测试 |
| customer-self-service-backend | `ArchitectureTests` | ArchUnit 验证 |
| policy-management-backend | `PolicyInformationHolderTests` | @WebMvcTest 策略接口 |
| policy-management-backend | `PolicyRepositoryTests` | @DataJpaTest 数据层 |
| policy-management-backend | `RiskManagementMessageProducerTests` | 嵌入式 ActiveMQ 消息测试 |
| policy-management-backend | `ArchitectureTests` | ArchUnit 验证 |

---

## 四、安装前端依赖

```powershell
cd d:\AAAresearch\microservices\LakeSideMutual-Micro-Mono\LakesideMutual-master

cd customer-self-service-frontend ; npm install ; cd ..
cd customer-management-frontend   ; npm install ; cd ..
cd policy-management-frontend     ; npm install ; cd ..
cd risk-management-server         ; npm install ; cd ..
cd risk-management-client         ; npm install ; cd ..
```

---

## 五、分窗口启动所有服务

**请打开 9 个独立的 PowerShell 窗口**，每个窗口运行一个服务。

### 窗口 1 — Spring Boot Admin（监控，先启）

```powershell
cd d:\AAAresearch\microservices\LakeSideMutual-Micro-Mono\LakesideMutual-master\spring-boot-admin
mvn spring-boot:run
# 启动成功标志：Tomcat started on port 9000
# 访问：http://localhost:9000
```

### 窗口 2 — Customer Core（基础数据服务，先启）

```powershell
cd d:\AAAresearch\microservices\LakeSideMutual-Micro-Mono\LakesideMutual-master\customer-core
mvn spring-boot:run
# 启动成功标志：Tomcat started on port 8110
# DataLoader 会自动插入 50 个测试客户（来自 mock_customers_small.csv）
# Swagger UI：http://localhost:8110/swagger-ui/index.html
# H2 控制台：http://localhost:8110/console（用户名/密码：sa/sa）
```

### 窗口 3 — Policy Management Backend（保单+ActiveMQ Broker，先启）

```powershell
cd d:\AAAresearch\microservices\LakeSideMutual-Micro-Mono\LakesideMutual-master\policy-management-backend
mvn spring-boot:run
# 启动成功标志：Tomcat started on port 8090
# ActiveMQ broker 监听：TCP:61616，STOMP:61613
# Swagger UI：http://localhost:8090/swagger-ui/index.html
```

### 窗口 4 — Customer Management Backend

```powershell
cd d:\AAAresearch\microservices\LakeSideMutual-Micro-Mono\LakesideMutual-master\customer-management-backend
mvn spring-boot:run
# 启动成功标志：Tomcat started on port 8100
# Swagger UI：http://localhost:8100/swagger-ui/index.html
```

### 窗口 5 — Customer Self-Service Backend

```powershell
cd d:\AAAresearch\microservices\LakeSideMutual-Micro-Mono\LakesideMutual-master\customer-self-service-backend
mvn spring-boot:run
# 启动成功标志：Tomcat started on port 8080
# Swagger UI：http://localhost:8080/swagger-ui/index.html
```

### 窗口 6 — Risk Management Server（Node.js + gRPC）

```powershell
cd d:\AAAresearch\microservices\LakeSideMutual-Micro-Mono\LakesideMutual-master\risk-management-server
npm start
# 启动成功标志：gRPC Server running on port 50051
# 注意：需要 policy-management-backend 先启动（STOMP broker）
```

### 窗口 7 — Customer Self-Service Frontend（React，端口 3000）

```powershell
cd d:\AAAresearch\microservices\LakeSideMutual-Micro-Mono\LakesideMutual-master\customer-self-service-frontend
npm start
# 访问：http://localhost:3000
# 功能：客户自助服务（注册、登录、查看保单、申请报价）
```

### 窗口 8 — Policy Management Frontend（Vue 2，端口 3010）

```powershell
cd d:\AAAresearch\microservices\LakeSideMutual-Micro-Mono\LakesideMutual-master\policy-management-frontend
# 必须设置此环境变量！Vue CLI 4 / Webpack 4 与 Node.js 17+ 的 OpenSSL 3 不兼容
$env:NODE_OPTIONS="--openssl-legacy-provider"
npm start
# 访问：http://localhost:3010
# 功能：保单管理（运营人员操作）
```

### 窗口 9 — Customer Management Frontend（React+Redux，端口 3020）

```powershell
cd d:\AAAresearch\microservices\LakeSideMutual-Micro-Mono\LakesideMutual-master\customer-management-frontend
npm start
# 访问：http://localhost:3020
# 功能：客户管理（运营人员操作）
```

---

## 六、端口速查表

| 服务 | 端口 | 类型 |
|------|------|------|
| customer-self-service-frontend | 3000 | HTTP/React |
| policy-management-frontend | 3010 | HTTP/Vue |
| customer-management-frontend | 3020 | HTTP/React |
| customer-self-service-backend | 8080 | HTTP/REST |
| policy-management-backend | 8090 | HTTP/REST |
| customer-management-backend | 8100 | HTTP/REST |
| customer-core | 8110 | HTTP/REST |
| spring-boot-admin | 9000 | HTTP |
| policy-management-backend (ActiveMQ STOMP) | 61613 | STOMP |
| policy-management-backend (ActiveMQ TCP) | 61616 | TCP |
| risk-management-server | 50051 | gRPC |

---

## 七、API Keys（用于后端间调用）

> **重要**：customer-core 要求 `Bearer ` 前缀！例如 `Authorization: Bearer b318ad736c6c844b`
> policy-management-backend 和 customer-management-backend **无需 API Key**（开放访问）。

| 服务 | Header | 格式 |
|------|--------|------|
| customer-core | Authorization | `Bearer b318ad736c6c844b`（需要 Bearer 前缀） |
| customer-self-service-backend | X-Auth-Token | JWT Token（通过 `/auth` 登录获取） |
| policy-management-backend | 无需认证 | 直接访问 |
| customer-management-backend | 无需认证 | 直接访问 |

---

## 八、端到端测试

运行自动化测试脚本（需要所有服务已启动）：

```powershell
cd d:\AAAresearch\microservices\LakeSideMutual-Micro-Mono\LakesideMutual-master

# 脚本 1：核心 REST API + 业务流程测试（只需后端启动）
.\e2e-test.ps1

# 脚本 2：WebSocket 聊天 + gRPC + 前端可达性（需要所有服务 + 前端启动）
.\e2e-test-extra.ps1
```

### 前端手动测试路径

1. **客户自助服务**（http://localhost:3000）
   - 点击 "Sign Up" 注册新账号
   - 登录后查看个人资料
   - 提交保险报价请求

2. **保单管理**（http://localhost:3010）
   - 查看所有保单
   - 查看客户列表
   - 处理报价请求（接受/拒绝）

3. **客户管理**（http://localhost:3020）
   - 查看客户列表
   - 查看客户互动日志
   - 与客户聊天（WebSocket）

---

## 九、常见问题排查

### Q: Maven 编译报错 `release version 21 not supported`
**A:** 已修复，所有 pom.xml 已改为 Java 17。

### Q: 前端启动报 `Error: error:0308010C:digital envelope routines::unsupported`
**A:** Node.js 17+ 的 OpenSSL 兼容性问题（react-scripts 4.x 才有此问题，react-scripts 5.x 不应有）。
如仍出现，在启动前设置：
```powershell
$env:NODE_OPTIONS="--openssl-legacy-provider"
npm start
```

### Q: risk-management-server 启动报 STOMP 连接拒绝
**A:** 必须先启动 `policy-management-backend`（它包含 ActiveMQ broker）。

### Q: Spring Boot Admin 显示服务 DOWN
**A:** Spring Boot Admin client 注册需要几秒延迟，稍候刷新即可。各服务启动后约 30 秒会注册。

### Q: H2 数据在重启后丢失
**A:** 默认配置为 `create-drop`，每次重启清空。若需持久化，修改 `application.properties`：
```properties
spring.jpa.hibernate.ddl-auto=update
```

### Q: 运行 `mvn test` 时 customer-self-service-backend 测试报 ActiveMQ 连接错误
**A:** 测试使用嵌入式 ActiveMQ，不依赖外部服务，正常情况应可通过。如报错，检查是否有端口冲突（61616）。

---

## 十、Risk Management Client（gRPC CLI 工具）

在 `risk-management-server` 启动后，可用 CLI 工具生成风险报告：

```powershell
cd d:\AAAresearch\microservices\LakeSideMutual-Micro-Mono\LakesideMutual-master\risk-management-client
# Windows 上运行（需要至少创建过一份保单才有数据）：
.\riskmanager.bat run C:\Temp\risk-report.csv
```

报告以 CSV 格式输出，包含有保单客户的风险因子评估。
