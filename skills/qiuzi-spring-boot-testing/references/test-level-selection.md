# 测试层级选择

先验证测试真正要证明的行为，再选择最低层级。不要因为项目使用 Spring Boot 就默认启动 Spring。

| 需要证明的行为 | 选择 | 关键验证 | 不应验证 |
| --- | --- | --- | --- |
| Service 业务分支、转换、默认值、异常、协作参数 | JUnit 5 + Mockito | 返回值、异常、`ArgumentCaptor` 捕获参数、禁止的写操作 | Spring 注入、HTTP 状态、数据库 SQL |
| Controller 作为普通 Java 类的委托或返回包装 | 纯 Mockito 单测 | 入参透传、返回对象、业务异常契约 | 路由、序列化、`@Valid`、`@ControllerAdvice` |
| 路由、绑定、校验、状态码、JSON、全局异常处理 | `@WebMvcTest` + `MockMvc` | HTTP 状态、错误响应、请求映射、服务调用 | 数据库和无关 Bean 装配 |
| 配置绑定、AOP、缓存、异步代理、条件装配、事务行为 | 缩窄 `@SpringBootTest(classes = {...})` 或 `ApplicationContextRunner` | 真实代理或上下文行为 | 无关应用模块、真实外部基础设施 |
| 数据库、消息队列、RPC 等基础设施协作 | 隔离集成测试 | 真实边界交互和清理策略 | 默认在快速单测阶段执行 |

## 纯 Mockito 单测

默认测试 Service、命令执行器、转换器和普通组件。让被测对象保持真实，仅替换其外部依赖。

```java
@ExtendWith(MockitoExtension.class)
class UserServiceTest {

    @Mock
    private UserRepository userRepository;

    @InjectMocks
    private UserService userService;

    @Test
    void createRejectsDuplicateUsername() {
        UserCreateCmd cmd = new UserCreateCmd("alice");
        when(userRepository.existsByUsername("alice")).thenReturn(true);

        assertThatThrownBy(() -> userService.create(cmd))
                .isInstanceOf(BusinessException.class);

        verify(userRepository, never()).save(any());
    }
}
```

- 仅当业务契约明确时，补充错误码或异常消息断言。
- 当需要验证保存对象字段时，用 `ArgumentCaptor<User>` 捕获 `save` 入参，不要只写 `verify(repository).save(any())`。
- 不要为纯业务逻辑加入 `@SpringBootTest`、`@Order` 或固定测试日志。

## Web 切片测试

需要验证 HTTP 行为时使用 `@WebMvcTest`。将 Controller 保持真实；通过项目当前兼容的 Mock Bean 注解替换其外部 Service，具体注解选择见 `version-compatibility.md`。

```java
@WebMvcTest(UserController.class)
class UserControllerTest {

    @Autowired
    private MockMvc mockMvc;

    // 示例使用旧项目常见的 @MockBean；新项目按兼容资料替换为 @MockitoBean。
    @MockBean
    private UserService userService;

    @Test
    void getByIdReturnsUserJson() throws Exception {
        when(userService.getById(1L)).thenReturn(new UserDto(1L, "alice"));

        mockMvc.perform(get("/users/{id}", 1L))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.name").value("alice"));
    }
}
```

- 当前项目使用 `@MockitoBean` 时，替换示例中的 `@MockBean`，不要在同一字段上重复标注两者。
- Controller 纯单测可断言业务异常向上抛出；Web 切片测试应断言异常经 `@ControllerAdvice` 处理后的 HTTP 响应。
- 若全局异常处理器或安全配置影响结果，显式导入最少必要配置，不要回退到全量应用上下文。

## 缩窄容器测试

只有真实容器行为是断言对象时才启动上下文。

- 配置属性或条件装配：优先 `ApplicationContextRunner`。
- MVC 行为：优先 `@WebMvcTest`。
- AOP、异步代理、缓存或事务：使用显式 `classes = {...}` 的 `@SpringBootTest`，并替换外部基础设施 Bean。

给这类测试标记项目约定的慢测标签（例如 `@Tag("integration")`），但不要把所有单测和切片测试都标为集成测试。

## 真实集成测试

真实基础设施是被测契约的一部分时才使用。优先 Testcontainers、专用测试 Profile 或可控替身，并清理外部状态。将其与快速单测分离到项目已配置的 Failsafe 或 Gradle 集成测试任务中。

不要用一次全量 `@SpringBootTest` 和真实数据库连接替代本应是纯单测的业务逻辑验证。
