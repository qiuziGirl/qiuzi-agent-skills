---
name: qiuzi-spring-boot-testing
description: 编写、补充、修改和评审 Spring Boot Java 项目的 JUnit 5 与 Mockito 测试。用于 Service、Controller、组件及配置相关测试的分层选择、Mock 与断言设计、Spring 测试上下文控制、Surefire/Failsafe 执行核对，以及测试代码评审；当用户要求新增单测、修复测试、提高测试质量、检查测试覆盖与顺序依赖时使用。
---

# Spring Boot 分层测试

以最低足够的测试层级验证业务行为：默认纯 Mockito 单测；仅在 HTTP 契约、Spring 容器行为或真实基础设施不可替代时升级测试层级。

## 工作流程

### 1. 先确认项目事实

执行任何测试编写、修改或评审前：

1. 在实际仓库根目录读取 `AGENTS.md`、`pom.xml` 或 `build.gradle(.kts)`、相关模块构建文件。
2. 检查现有 `src/test` 测试、父 POM/BOM、JUnit/Mockito/Spring Test 依赖与 Surefire/Failsafe（或 Gradle test task）配置。
3. 顺着被测公开方法的真实调用链确认：输入、业务分支、可观察输出、副作用、异常契约与外部依赖。
4. 复用项目已有的测试命名、断言库和测试启动方式；不要凭本 Skill 假设模块名、JDK 路径或插件配置。

### 2. 选择最低足够的层级

按以下顺序判断，命中前一项即不要升级：

1. 只验证业务逻辑、数据转换、异常或外部协作：纯 Mockito 单测。
2. 需要验证路由、参数绑定、校验或 HTTP 错误响应：Web 切片测试。
3. 需要验证配置绑定、AOP、缓存、异步代理、条件装配或事务行为：缩窄 Spring 上下文测试。
4. 必须访问真实数据库、消息中间件、RPC 或其他基础设施：隔离的集成测试。

读取 [references/test-level-selection.md](references/test-level-selection.md) 获取选型边界与示例。

### 3. 编写或修改测试

遵循以下规则：

- 测试必须独立、可重复执行；不要默认添加 `@TestMethodOrder`、`@Order`、共享可变状态或依赖其他用例执行结果。
- 默认使用 `@ExtendWith(MockitoExtension.class)`、`@Mock` 与 `@InjectMocks` 编写纯单测；不要为普通 Service 逻辑启动 Spring 容器。
- 每个测试验证一个清晰的业务场景。断言返回值、状态变化、抛出的业务异常或外部协作的实际参数；不要只验证“调用过”，也不要保留 `assertTrue(true)`、`assertNull(null)` 等无效断言。
- 被测方法内部构造并传给依赖的对象，使用 `ArgumentCaptor` 断言关键字段。若使用 Mockito matcher，同一次调用的其他参数也使用 matcher（如 `eq(...)`），不得混用 matcher 与裸值。
- 对异常场景，断言异常类型；仅当异常消息是业务契约时才断言消息或错误码。异常发生后，验证不应发生的写操作未发生。
- 不强制测试首尾日志。只在异步、复杂数据构造或失败诊断确有必要时添加少量日志。
- 优先通过公开行为验证。不要默认用反射测试私有方法；复杂私有逻辑应优先提取为可测试协作者。
- 优先重构或引入适配层，避免静态 Mock。确需使用 `MockedStatic` 时，先核对项目 Mockito 配置，再以 `try-with-resources` 限定作用域。
- 容器测试只装配最小必要 Bean 和配置；不要默认使用扫描全部应用的 `@SpringBootTest`。

读取 [references/version-compatibility.md](references/version-compatibility.md) 后再选择 Spring 的 Mock Bean 注解或处理静态 Mock。

### 4. 运行并如实报告验证

1. 先按构建文件与插件配置确认测试类是否会被当前生命周期发现。
2. 优先执行受影响模块和目标测试类；仅在有必要时扩大到模块测试或全仓测试。
3. 报告实际执行的命令、通过/失败结果、未执行项目及其原因。构建通过不等于容器、真实数据库或端到端场景已验收。

读取 [references/maven-test-lifecycle.md](references/maven-test-lifecycle.md) 获取 Maven、Gradle、Surefire/Failsafe 和 Windows PowerShell 命令选择规则。

## 评审测试改动

评审时先读取真实改动与被测实现，再按以下维度输出结论：

1. **测试层级判断**：当前层级是否过重或缺少 HTTP/容器/基础设施行为覆盖。
2. **已覆盖行为**：列出每个用例验证的业务分支、异常或副作用。
3. **关键缺口**：只报告有真实调用链依据的分支、边界、异常、参数或副作用缺失。
4. **技术风险**：顺序依赖、共享状态、无效断言、只验交互未验数据、错误使用 matcher、未被构建生命周期发现、过度容器化等。
5. **验证建议**：给出与当前项目配置匹配的最小命令，并区分已执行和建议执行。

没有发现可证实问题时，明确说明“不产生改动”。若根据评审意见修改测试文件，只修改文件；不要执行 `git add`、提交或推送。

## 输出要求

编写/修改任务至少说明：

- 所选测试层级及原因；
- 覆盖的业务行为和异常路径；
- 实际执行的验证命令与结果；
- 尚未覆盖的真实环境或集成验证边界。

评审任务使用“测试层级判断、已覆盖行为、关键缺口、技术风险、验证建议”五段式；面向用户使用中文。

## 参考资料

- [测试层级选择](references/test-level-selection.md)：在纯单测、Web 切片、容器测试与集成测试之间选择。
- [版本兼容](references/version-compatibility.md)：检查项目依赖后选择 Mock Bean 注解与 Mockito 能力。
- [测试生命周期](references/maven-test-lifecycle.md)：确认测试命名、执行生命周期和 Windows 命令。
