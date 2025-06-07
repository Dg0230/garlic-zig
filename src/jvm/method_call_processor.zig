//! JVM 方法调用处理器
//! 实现 invokevirtual, invokespecial, invokestatic, invokeinterface 等方法调用指令的处理逻辑

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const instructions = @import("instructions.zig");
const stack = @import("stack.zig");
const locals = @import("locals.zig");

const Opcode = instructions.Opcode;
const OperandStack = stack.OperandStack;
const LocalVariableTable = locals.LocalVariableTable;
const StackValue = stack.StackValue;
const ValueType = stack.ValueType;

/// 方法调用错误类型
pub const MethodCallError = error{
    InvalidMethodReference,
    MethodNotFound,
    InvalidSignature,
    IncompatibleTypes,
    StackUnderflow,
    StackOverflow,
    InvalidOperation,
    TypeMismatch,
    OutOfMemory,
};

/// 方法描述符
pub const MethodDescriptor = struct {
    class_name: []const u8,
    method_name: []const u8,
    signature: []const u8,
    parameter_count: u8,
    return_type: ValueType,
    is_static: bool,
    is_constructor: bool,

    pub fn init(class_name: []const u8, method_name: []const u8, signature: []const u8) MethodDescriptor {
        return MethodDescriptor{
            .class_name = class_name,
            .method_name = method_name,
            .signature = signature,
            .parameter_count = parseParameterCount(signature),
            .return_type = parseReturnType(signature),
            .is_static = false,
            .is_constructor = std.mem.eql(u8, method_name, "<init>"),
        };
    }

    /// 解析方法签名中的参数数量
    fn parseParameterCount(signature: []const u8) u8 {
        var count: u8 = 0;
        var i: usize = 1; // 跳过开头的 '('

        while (i < signature.len and signature[i] != ')') {
            switch (signature[i]) {
                'B', 'C', 'F', 'I', 'S', 'Z' => {
                    count += 1;
                    i += 1;
                },
                'D', 'J' => {
                    count += 2; // long 和 double 占用两个栈槽
                    i += 1;
                },
                'L' => {
                    count += 1;
                    // 跳过类名直到 ';'
                    while (i < signature.len and signature[i] != ';') {
                        i += 1;
                    }
                    i += 1; // 跳过 ';'
                },
                '[' => {
                    count += 1;
                    i += 1;
                    // 跳过数组类型描述符
                    while (i < signature.len and signature[i] == '[') {
                        i += 1;
                    }
                    if (i < signature.len) {
                        if (signature[i] == 'L') {
                            while (i < signature.len and signature[i] != ';') {
                                i += 1;
                            }
                        }
                        i += 1;
                    }
                },
                else => i += 1,
            }
        }

        return count;
    }

    /// 解析方法签名中的返回类型
    fn parseReturnType(signature: []const u8) ValueType {
        // 找到 ')' 后的返回类型
        var i: usize = 0;
        while (i < signature.len and signature[i] != ')') {
            i += 1;
        }

        if (i + 1 >= signature.len) {
            return .reference; // 默认返回引用类型
        }

        return switch (signature[i + 1]) {
            'V' => .reference, // void 方法不返回值，但我们用 reference 表示
            'I', 'B', 'C', 'S', 'Z' => .int,
            'J' => .long,
            'F' => .float,
            'D' => .double,
            'L', '[' => .reference,
            else => .reference,
        };
    }
};

/// 方法调用结果
pub const MethodCallResult = struct {
    return_value: ?StackValue = null,
    exception: ?StackValue = null,
    should_return: bool = false,
};

/// 方法调用处理器
pub const MethodCallProcessor = struct {
    allocator: Allocator,
    builtin_methods: std.HashMap([]const u8, *const fn (*MethodCallProcessor, []StackValue) MethodCallError!MethodCallResult, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),

    pub fn init(allocator: Allocator) !MethodCallProcessor {
        var processor = MethodCallProcessor{
            .allocator = allocator,
            .builtin_methods = std.HashMap([]const u8, *const fn (*MethodCallProcessor, []StackValue) MethodCallError!MethodCallResult, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
        };

        // 注册内置方法
        try processor.registerBuiltinMethods();

        return processor;
    }

    pub fn deinit(self: *MethodCallProcessor) void {
        self.builtin_methods.deinit();
    }

    /// 注册内置方法
    fn registerBuiltinMethods(self: *MethodCallProcessor) !void {
        // System.out.println 方法
        try self.builtin_methods.put("java/io/PrintStream.println:(Ljava/lang/String;)V", systemOutPrintln);
        try self.builtin_methods.put("java/io/PrintStream.println:(I)V", systemOutPrintlnInt);
        try self.builtin_methods.put("java/io/PrintStream.println:()V", systemOutPrintlnEmpty);

        // Object 构造函数
        try self.builtin_methods.put("java/lang/Object.<init>:()V", objectInit);

        // String 相关方法
        try self.builtin_methods.put("java/lang/String.<init>:()V", stringInit);
        try self.builtin_methods.put("java/lang/String.length:()I", stringLength);
    }

    /// 处理 invokevirtual 指令
    pub fn processInvokeVirtual(
        self: *MethodCallProcessor,
        operands: []const u8,
        operand_stack: *OperandStack,
        constant_pool: anytype, // 常量池引用
    ) MethodCallError!MethodCallResult {
        if (operands.len < 2) return MethodCallError.InvalidMethodReference;

        const method_ref_index = (@as(u16, operands[0]) << 8) | @as(u16, operands[1]);
        const method_desc = try self.resolveMethodReference(method_ref_index, constant_pool);

        // 弹出参数和对象引用
        var args = try self.allocator.alloc(StackValue, method_desc.parameter_count + 1);
        defer self.allocator.free(args);

        // 从栈顶开始弹出参数（逆序）
        var i: usize = method_desc.parameter_count;
        while (i > 0) {
            i -= 1;
            args[i + 1] = try operand_stack.pop();
        }

        // 弹出对象引用（this）
        args[0] = try operand_stack.pop();

        return self.invokeMethod(method_desc, args);
    }

    /// 处理 invokespecial 指令
    pub fn processInvokeSpecial(
        self: *MethodCallProcessor,
        operands: []const u8,
        operand_stack: *OperandStack,
        constant_pool: anytype,
    ) MethodCallError!MethodCallResult {
        if (operands.len < 2) return MethodCallError.InvalidMethodReference;

        const method_ref_index = (@as(u16, operands[0]) << 8) | @as(u16, operands[1]);
        const method_desc = try self.resolveMethodReference(method_ref_index, constant_pool);

        // 弹出参数和对象引用
        var args = try self.allocator.alloc(StackValue, method_desc.parameter_count + 1);
        defer self.allocator.free(args);

        // 从栈顶开始弹出参数（逆序）
        var i: usize = method_desc.parameter_count;
        while (i > 0) {
            i -= 1;
            args[i + 1] = try operand_stack.pop();
        }

        // 弹出对象引用（this）
        args[0] = try operand_stack.pop();

        return self.invokeMethod(method_desc, args);
    }

    /// 处理 invokestatic 指令
    pub fn processInvokeStatic(
        self: *MethodCallProcessor,
        operands: []const u8,
        operand_stack: *OperandStack,
        constant_pool: anytype,
    ) MethodCallError!MethodCallResult {
        if (operands.len < 2) return MethodCallError.InvalidMethodReference;

        const method_ref_index = (@as(u16, operands[0]) << 8) | @as(u16, operands[1]);
        var method_desc = try self.resolveMethodReference(method_ref_index, constant_pool);
        method_desc.is_static = true;

        // 弹出参数（静态方法没有 this 引用）
        var args = try self.allocator.alloc(StackValue, method_desc.parameter_count);
        defer self.allocator.free(args);

        // 从栈顶开始弹出参数（逆序）
        var i: usize = method_desc.parameter_count;
        while (i > 0) {
            i -= 1;
            args[i] = try operand_stack.pop();
        }

        return self.invokeMethod(method_desc, args);
    }

    /// 处理 invokeinterface 指令
    pub fn processInvokeInterface(
        self: *MethodCallProcessor,
        operands: []const u8,
        operand_stack: *OperandStack,
        constant_pool: anytype,
    ) MethodCallError!MethodCallResult {
        if (operands.len < 4) return MethodCallError.InvalidMethodReference;

        const method_ref_index = (@as(u16, operands[0]) << 8) | @as(u16, operands[1]);
        const count = operands[2]; // 参数数量
        // operands[3] 必须为 0

        const method_desc = try self.resolveMethodReference(method_ref_index, constant_pool);

        // 弹出参数和对象引用
        var args = try self.allocator.alloc(StackValue, count);
        defer self.allocator.free(args);

        // 从栈顶开始弹出参数（逆序）
        var i: usize = count;
        while (i > 0) {
            i -= 1;
            args[i] = try operand_stack.pop();
        }

        return self.invokeMethod(method_desc, args);
    }

    /// 解析方法引用
    fn resolveMethodReference(self: *MethodCallProcessor, index: u16, constant_pool: anytype) MethodCallError!MethodDescriptor {
        _ = self;
        _ = index;
        _ = constant_pool;

        // 这里应该从常量池中解析方法引用
        // 目前返回一个模拟的方法描述符
        return MethodDescriptor{
            .class_name = "java/lang/Object",
            .method_name = "toString",
            .signature = "()Ljava/lang/String;",
            .parameter_count = 0,
            .return_type = .reference,
            .is_static = false,
            .is_constructor = false,
        };
    }

    /// 调用方法
    fn invokeMethod(self: *MethodCallProcessor, method_desc: MethodDescriptor, args: []StackValue) MethodCallError!MethodCallResult {
        // 构建方法的完整签名
        const full_signature = try std.fmt.allocPrint(self.allocator, "{s}.{s}:{s}", .{ method_desc.class_name, method_desc.method_name, method_desc.signature });
        defer self.allocator.free(full_signature);

        // 查找内置方法
        if (self.builtin_methods.get(full_signature)) |builtin_method| {
            return builtin_method(self, args);
        }

        // 如果不是内置方法，返回默认结果
        return MethodCallResult{
            .return_value = switch (method_desc.return_type) {
                .int => StackValue{ .int = 0 },
                .long => StackValue{ .long = 0 },
                .float => StackValue{ .float = 0.0 },
                .double => StackValue{ .double = 0.0 },
                .reference => StackValue{ .reference = null },
                .return_address => StackValue{ .return_address = 0 },
            },
        };
    }

    /// 检查是否为构造函数调用
    pub fn isConstructorCall(method_name: []const u8) bool {
        return std.mem.eql(u8, method_name, "<init>");
    }

    /// 检查是否为静态初始化方法
    pub fn isStaticInitializer(method_name: []const u8) bool {
        return std.mem.eql(u8, method_name, "<clinit>");
    }
};

// ==================== 内置方法实现 ====================

/// System.out.println(String) 实现
fn systemOutPrintln(processor: *MethodCallProcessor, args: []StackValue) MethodCallError!MethodCallResult {
    _ = processor;
    if (args.len < 2) return MethodCallError.InvalidSignature;

    // args[0] 是 PrintStream 对象引用
    // args[1] 是要打印的字符串

    // 这里应该实际打印字符串，目前只是模拟
    std.debug.print("[System.out.println] String argument\n", .{});

    return MethodCallResult{};
}

/// System.out.println(int) 实现
fn systemOutPrintlnInt(processor: *MethodCallProcessor, args: []StackValue) MethodCallError!MethodCallResult {
    _ = processor;
    if (args.len < 2) return MethodCallError.InvalidSignature;

    // args[0] 是 PrintStream 对象引用
    // args[1] 是要打印的整数
    const int_value = args[1].toInt() catch return MethodCallError.IncompatibleTypes;

    std.debug.print("[System.out.println] {d}\n", .{int_value});

    return MethodCallResult{};
}

/// System.out.println() 实现
fn systemOutPrintlnEmpty(processor: *MethodCallProcessor, args: []StackValue) MethodCallError!MethodCallResult {
    _ = processor;
    _ = args;

    std.debug.print("[System.out.println]\n", .{});

    return MethodCallResult{};
}

/// Object.<init>() 实现
fn objectInit(processor: *MethodCallProcessor, args: []StackValue) MethodCallError!MethodCallResult {
    _ = processor;
    if (args.len < 1) return MethodCallError.InvalidSignature;

    // args[0] 是对象引用，构造函数不返回值
    return MethodCallResult{};
}

/// String.<init>() 实现
fn stringInit(processor: *MethodCallProcessor, args: []StackValue) MethodCallError!MethodCallResult {
    _ = processor;
    if (args.len < 1) return MethodCallError.InvalidSignature;

    // args[0] 是 String 对象引用
    return MethodCallResult{};
}

/// String.length() 实现
fn stringLength(processor: *MethodCallProcessor, args: []StackValue) MethodCallError!MethodCallResult {
    _ = processor;
    if (args.len < 1) return MethodCallError.InvalidSignature;

    // args[0] 是 String 对象引用
    // 返回模拟的字符串长度
    return MethodCallResult{
        .return_value = StackValue{ .int = 5 }, // 模拟长度为 5
    };
}
