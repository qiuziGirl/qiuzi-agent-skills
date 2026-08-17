# 版本与依赖兼容

不要根据记忆猜测测试 API 是否存在。每次先读取当前模块和父构建文件，再复用项目中已能编译的测试写法。

## 检查顺序

1. 查找 Spring Boot 父 POM、BOM、Gradle plugin 或版本目录。
2. 查找 `spring-boot-starter-test`、JUnit Jupiter、Mockito、`spring-test` 与现有测试导入。
3. 查找现有 `@MockBean`、`@MockitoBean`、`MockedStatic` 和对应测试是否已通过构建。
4. 查找 Maven Surefire/Failsafe 或 Gradle 测试任务配置。

## Mock Bean 注解

容器测试只 Mock 外部依赖，不 Mock 被测 Controller 或 Service 本身。

| 条件 | 处理 |
| --- | --- |
| 项目已有可编译的 `org.springframework.test.context.bean.override.mockito.MockitoBean` 用法，或当前依赖明确提供该类 | 按项目现有写法使用 `@MockitoBean`。 |
| 项目已有可编译的 `org.springframework.boot.test.mock.mockito.MockBean` 用法，且未具备新的 Bean Override API | 沿用 `@MockBean`，不要在本次任务中无关迁移全部旧测试。 |
| 两者都无法从构建文件或现有源码确认 | 先确认 classpath/依赖版本；不要猜测注解包名或通过新增依赖碰运气。 |

在升级 Spring Boot 或 Spring Framework 时，先以当前项目依赖和官方迁移说明为准，再批量迁移 Mock Bean 注解。

## Mockito 规则

- 默认由 `spring-boot-starter-test` 或项目既有测试依赖提供 JUnit 5 与 Mockito；不要重复添加版本不一致的测试依赖。
- 不要默认添加 `mockito-inline`。只有真实项目配置明确要求并且无法通过重构避免时，才使用静态 Mock。
- 使用 `MockedStatic` 时必须采用 `try-with-resources`，将影响限制在单个测试方法。
- 使用 Mockito matcher 时，同一次调用的每个参数都采用 matcher：`eq("alice")`、`any(User.class)`；不要与裸值混用。
- 对 `void` 方法抛异常使用 `doThrow(...).when(mock).method(...)`；对返回值方法使用 `when(...).thenReturn(...)`。

## 断言库

优先使用当前项目已采用的断言库。新增项目通常可选 AssertJ 或 JUnit Assertions，但不要在一个测试类中无理由混用多种风格。

业务异常的消息、错误码、HTTP 响应字段只有在它们属于对外契约时才断言；否则优先断言异常类型和必要副作用。
