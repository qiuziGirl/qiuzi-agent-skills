# 测试命名与执行生命周期

构建文件和插件 `includes`/`excludes` 是唯一事实来源。执行前先检查实际项目配置，再选择命令。

## Maven 默认约定

在未被项目配置覆盖时：

| 类型 | 常见命名 | 常见插件与生命周期 | 定向执行参数 |
| --- | --- | --- | --- |
| 快速单测、切片测试 | `*Test`、`*Tests`、`Test*` | Surefire，`test` | `-Dtest=类名` |
| 集成测试 | `*IT`、`*ITCase`、`IT*` | Failsafe，`integration-test` / `verify` | `-Dit.test=类名` |

因此，创建 `UserControllerIT` 后不能只假设 `mvn test` 会执行它；必须确认 Failsafe 已配置，并用 `mvn verify` 或项目定义的集成测试命令。

## Maven 命令模板

将 `<module>` 和 `<TestClass>` 替换为真实值，且先确认模块选择与插件配置。

```powershell
# 单模块或多模块中的一个快速测试类
mvn -pl <module> -am -Dtest=<TestClass> test

# 一个由 Failsafe 管理的集成测试类
mvn -pl <module> -am -Dit.test=<TestClass> verify

# 执行模块完整快速测试集
mvn -pl <module> -am test
```

若项目通过 profile、属性或 `includes` 改写测试发现规则，以项目已有 CI 命令为准。

## Gradle 命令模板

```powershell
# 定向执行标准 test 任务中的测试
.\gradlew :<module>:test --tests '<package>.<TestClass>'

# 仅当项目已定义 integrationTest 任务时执行
.\gradlew :<module>:integrationTest --tests '<package>.<TestClass>'
```

不要为了执行集成测试临时创建 Gradle task；先遵循项目现有构建约定。

## Windows PowerShell 下选择 JDK

先读取构建文件中的 Java 目标版本，再确认对应的本机 JDK 变量和目录存在。不要盲目使用默认 `JAVA_HOME`。

```powershell
# 示例：项目目标为 Java 21，且本机已配置 JAVA21_HOME。
$env:JAVA_HOME = $env:JAVA21_HOME
$env:Path = "$env:JAVA_HOME\bin;$env:Path"
java -version
mvn -pl <module> -am -Dtest=<TestClass> test
```

如果不存在对应环境变量，报告阻塞原因；不要伪造路径或将不匹配的 JDK 结果描述为已验证。
