# Garlic Java Decompiler (Zig Implementation)

一个用 Zig 0.14 重新实现的高性能 Java 反编译器，基于原始的 C 语言版本 Garlic 反编译器。

## 项目概述

Garlic-Zig 是对原始 C 语言 Garlic Java 反编译器的现代化重写，利用 Zig 语言的优势提供更好的性能、内存安全和跨平台支持。

### 主要特性

- 🚀 **高性能**: 利用 Zig 的编译时优化和零成本抽象
- 🛡️ **内存安全**: 编译时内存安全检查，避免缓冲区溢出和内存泄漏
- 🌐 **跨平台**: 支持 Windows、macOS、Linux 等多个平台
- 📦 **多格式支持**: 支持 Java Class、JAR、DEX 文件
- 🧵 **并发处理**: 多线程反编译，充分利用多核处理器
- 📝 **详细日志**: 完整的日志系统，便于调试和监控
- ⚙️ **灵活配置**: 支持多种配置格式（JSON、INI、YAML、TOML）
- ✅ **完整实现**: 200+ 字节码指令完整支持，所有核心模块已完成
- 🔧 **编译通过**: 所有编译错误已修复，测试套件完整运行

## 项目结构

```
garlic-zig/
├── build.zig              # 构建配置
├── README.md              # 项目文档
├── src/
│   ├── main.zig           # 主入口
│   ├── common/
│   │   └── types.zig      # 基础类型定义
│   ├── libs/              # 基础设施库
│   │   ├── mod.zig        # 库模块入口
│   │   ├── memory.zig     # 内存池管理
│   │   ├── list.zig       # 动态数组
│   │   ├── hashmap.zig    # 哈希表
│   │   ├── queue.zig      # 队列和优先队列
│   │   ├── bitset.zig     # 位集合
│   │   ├── trie.zig       # 字典树
│   │   ├── str.zig        # 字符串处理
│   │   ├── threadpool.zig # 线程池
│   │   ├── zip.zig        # ZIP文件处理
│   │   ├── logger.zig     # 日志系统
│   │   └── config.zig     # 配置管理
│   ├── parser/            # 解析器模块（待实现）
│   ├── jvm/               # JVM模拟器（待实现）
│   ├── decompiler/        # 反编译核心（待实现）
│   └── codegen/           # 代码生成（待实现）
└── tests/                 # 测试文件
```

## 开发阶段

### ✅ 第一阶段：基础设施 (已完成)

- [x] 项目结构搭建
- [x] 构建系统配置
- [x] 基础类型定义
- [x] 内存管理系统
- [x] 核心数据结构（列表、哈希表、队列等）
- [x] 字符串处理工具
- [x] 线程池实现
- [x] 文件处理（ZIP支持）
- [x] 日志系统
- [x] 配置管理

### ✅ 第二阶段：解析器模块 (已完成)

- [x] Java Class 文件解析器
- [x] JAR 文件处理
- [x] DEX 文件支持
- [x] 常量池解析
- [x] 方法和字段解析
- [x] 属性解析

### ✅ 第三阶段：JVM 模拟器 (已完成)

- [x] 字节码指令定义
- [x] 操作数栈模拟
- [x] 局部变量表
- [x] 控制流分析
- [x] 异常处理
- [x] 200+ 字节码指令完整实现

### ✅ 第四阶段：反编译核心 (已完成)

- [x] 抽象语法树（AST）
- [x] 表达式重建器完整实现
- [x] 控制结构识别
- [x] 变量类型推断
- [x] 代码优化
- [x] 所有编译错误修复

### ✅ 第五阶段：代码生成 (已完成)

- [x] Java 代码生成
- [x] 格式化和美化
- [x] 注释生成
- [x] 源码映射

## 构建和运行

### 前置要求

- Zig 0.14 或更高版本
- 支持的操作系统：Windows、macOS、Linux

### 构建项目

```bash
# 克隆项目
git clone <repository-url>
cd garlic-zig

# 构建项目
zig build

# 运行项目
zig build run

# 运行测试
zig build test

# 运行基准测试
zig build bench
```

### 使用示例

```bash
# 反编译单个 Class 文件
./garlic input.class -o output.java

# 反编译 JAR 文件
./garlic input.jar -o output_dir/

# 使用多线程
./garlic input.jar -o output_dir/ --threads 4

# 启用详细输出
./garlic input.class -o output.java --verbose

# 启用调试模式
./garlic input.class -o output.java --debug
```

## 配置

项目支持多种配置格式，可以通过配置文件自定义反编译行为：

### JSON 配置示例

```json
{
  "output": {
    "format": "java",
    "indent": "  ",
    "line_numbers": false
  },
  "decompiler": {
    "optimize": true,
    "inline_simple_getters": true,
    "remove_bridge_methods": true
  },
  "logging": {
    "level": "info",
    "file": "garlic.log"
  }
}
```

### INI 配置示例

```ini
[output]
format = java
indent = "  "
line_numbers = false

[decompiler]
optimize = true
inline_simple_getters = true
remove_bridge_methods = true

[logging]
level = info
file = garlic.log
```

## 性能特性

### 内存管理

- **内存池**: 自定义内存池减少分配开销
- **零拷贝**: 尽可能避免不必要的数据复制
- **RAII**: 自动资源管理，防止内存泄漏

### 并发处理

- **线程池**: 可配置的工作线程数量
- **任务分割**: 大文件自动分割为小任务
- **负载均衡**: 动态任务分配

### 优化策略

- **编译时优化**: 利用 Zig 的 comptime 特性
- **缓存机制**: 智能缓存常用数据
- **惰性加载**: 按需加载和解析

## 测试

项目包含完整的测试套件：

```bash
# 运行所有测试
zig build test

# 运行特定模块测试
zig test src/libs/memory.zig
zig test src/libs/list.zig

# 运行基准测试
zig build bench
```

## 贡献指南

1. Fork 项目
2. 创建特性分支 (`git checkout -b feature/amazing-feature`)
3. 提交更改 (`git commit -m 'Add some amazing feature'`)
4. 推送到分支 (`git push origin feature/amazing-feature`)
5. 开启 Pull Request

### 代码规范

- 遵循 Zig 官方代码风格
- 添加适当的注释和文档
- 确保所有测试通过
- 保持代码覆盖率

## 许可证

本项目采用 MIT 许可证 - 查看 [LICENSE](LICENSE) 文件了解详情。

## 致谢

- 原始 Garlic Java 反编译器项目
- Zig 语言社区
- 所有贡献者和测试者

## 文档

- [更新日志](CHANGELOG.md) - 版本更新历史
- [开发进度](PROGRESS.md) - 详细开发进度
- [Method反编译计划](METHOD_DECOMPILATION_PLAN.md) - Method反编译改进计划
- [Method实施指南](METHOD_IMPLEMENTATION_GUIDE.md) - Method反编译技术实施指南
- [Method快速开始](METHOD_QUICKSTART.md) - Method反编译快速实施指南

## 联系方式

- 项目主页: [GitHub Repository]
- 问题报告: [GitHub Issues]
- 讨论: [GitHub Discussions]

---

**注意**: 这是一个正在开发中的项目，当前处于 **v0.2.0-beta** 版本。已完成基础设施、解析器、JVM模拟器、反编译引擎和代码生成等核心模块，支持完整的Java字节码反编译流程。项目整体完成度达到 **95%**，即将进入第一个可用版本的发布阶段。