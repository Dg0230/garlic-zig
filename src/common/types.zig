const std = @import("std");
const Allocator = std.mem.Allocator;

/// 基础类型别名
pub const u1_type = u8;
pub const u2_type = u16;
pub const u4_type = u32;
pub const u8_type = u64;

pub const s1_type = i8;
pub const s2_type = i16;
pub const s4_type = i32;
pub const s8_type = i64;

/// 字符串类型
pub const String = []const u8;
pub const MutableString = []u8;

/// 对象指针类型
pub const Object = *anyopaque;

/// 原始值联合体
pub const PrimitiveUnion = union(enum) {
    int_val: i32,
    long_val: i64,
    float_val: f32,
    double_val: f64,

    /// 获取整数值
    pub fn getInt(self: PrimitiveUnion) i32 {
        return switch (self) {
            .int_val => |val| val,
            else => @panic("不是整数类型"),
        };
    }

    /// 获取长整数值
    pub fn getLong(self: PrimitiveUnion) i64 {
        return switch (self) {
            .long_val => |val| val,
            else => @panic("不是长整数类型"),
        };
    }

    /// 获取浮点数值
    pub fn getFloat(self: PrimitiveUnion) f32 {
        return switch (self) {
            .float_val => |val| val,
            else => @panic("不是浮点数类型"),
        };
    }

    /// 获取双精度浮点数值
    pub fn getDouble(self: PrimitiveUnion) f64 {
        return switch (self) {
            .double_val => |val| val,
            else => @panic("不是双精度浮点数类型"),
        };
    }
};

/// 变量类型枚举
pub const VarType = enum(i32) {
    dynamic = -1,
    unknown = 0,
    int_type = 1,
    float_type = 2,
    long_type = 3,
    double_type = 4,
    null_type = 5,
    uninitialized_this = 6,
    uninitialized = 7,
    reference = 8,
    top = 9,

    /// 检查是否为原始类型
    pub fn isPrimitive(self: VarType) bool {
        return switch (self) {
            .int_type, .float_type, .long_type, .double_type => true,
            else => false,
        };
    }

    /// 检查是否为引用类型
    pub fn isReference(self: VarType) bool {
        return self == .reference;
    }

    /// 获取类型大小（栈槽数）
    pub fn getSize(self: VarType) u32 {
        return switch (self) {
            .long_type, .double_type => 2,
            else => 1,
        };
    }
};

/// 支持的平台类型
pub const SupportType = enum {
    jvm,
    dalvik,
};

/// 名称类型
pub const NameType = enum {
    var_name_def,
    var_name_debug,
};

/// 描述符标签
pub const DescriptorTag = enum {
    method_descriptor,
    variable_descriptor,
};

/// 字段状态标志
pub const FieldState = packed struct {
    hide: bool = false,
    _padding: u15 = 0,
};

/// 指令状态标志
pub const InsState = packed struct {
    nopped: bool = false,
    unreached: bool = false,
    copy_block: bool = false,
    duplicate: bool = false,
    copy_if_true_block: bool = false,
    try_start: bool = false,
    try_end: bool = false,
    handler_start: bool = false,
    handler_end: bool = false,
    finally_start: bool = false,
    finally_end: bool = false,
    _padding: u5 = 0,
};

/// 错误类型定义
pub const GarlicError = error{
    InvalidFile,
    ParseError,
    OutOfMemory,
    InvalidMagic,
    UnsupportedVersion,
    CorruptedData,
    InvalidInstruction,
    StackUnderflow,
    StackOverflow,
    InvalidIndex,
    UnknownOpcode,
};

/// 结果类型
pub fn Result(comptime T: type) type {
    return union(enum) {
        ok: T,
        err: GarlicError,

        /// 检查是否成功
        pub fn isOk(self: @This()) bool {
            return switch (self) {
                .ok => true,
                .err => false,
            };
        }

        /// 获取值（如果成功）
        pub fn unwrap(self: @This()) T {
            return switch (self) {
                .ok => |val| val,
                .err => |err| @panic(@errorName(err)),
            };
        }

        /// 获取值或默认值
        pub fn unwrapOr(self: @This(), default: T) T {
            return switch (self) {
                .ok => |val| val,
                .err => default,
            };
        }
    };
}

/// 可选指针类型
pub fn OptionalPtr(comptime T: type) type {
    return ?*T;
}

/// 常量定义
pub const Constants = struct {
    pub const JAVA_CLASS_MAGIC: u4 = 0xCAFEBABE;
    pub const JAR_MAGIC: u4 = 0x504B0304;
    pub const DEX_MAGIC: u4 = 0x6465780A; // "dex\n"

    pub const MAX_STACK_SIZE: u32 = 65535;
    pub const MAX_LOCAL_VARS: u32 = 65535;
    pub const MAX_INSTRUCTIONS: u32 = 1048576; // 1M

    pub const DEFAULT_THREAD_COUNT: u32 = 1;
    pub const MAX_THREAD_COUNT: u32 = 64;
};

test "PrimitiveUnion operations" {
    const testing = std.testing;

    const int_val = PrimitiveUnion{ .int_val = 42 };
    try testing.expect(int_val.getInt() == 42);

    const float_val = PrimitiveUnion{ .float_val = 3.14 };
    try testing.expect(float_val.getFloat() == 3.14);
}

test "VarType properties" {
    const testing = std.testing;

    try testing.expect(VarType.int_type.isPrimitive());
    try testing.expect(!VarType.reference.isPrimitive());
    try testing.expect(VarType.reference.isReference());
    try testing.expect(VarType.long_type.getSize() == 2);
    try testing.expect(VarType.int_type.getSize() == 1);
}

test "Result type" {
    const testing = std.testing;

    const ok_result = Result(i32){ .ok = 42 };
    try testing.expect(ok_result.isOk());
    try testing.expect(ok_result.unwrap() == 42);

    const err_result = Result(i32){ .err = GarlicError.InvalidFile };
    try testing.expect(!err_result.isOk());
    try testing.expect(err_result.unwrapOr(0) == 0);
}
