//! Java Class 文件字节码解析器
//! 负责解析 Java Class 文件的二进制格式，包括魔数验证、版本检查、常量池解析等

const std = @import("std");
const types = @import("../common/types.zig");
const Allocator = std.mem.Allocator;

/// Java Class 文件魔数 (0xCAFEBABE)
const JAVA_MAGIC: u32 = 0xCAFEBABE;

/// 支持的 Java 版本范围
const MIN_MAJOR_VERSION: u16 = 45; // Java 1.1
const MAX_MAJOR_VERSION: u16 = 65; // Java 21

/// 访问标志位定义
const AccessFlags = struct {
    const PUBLIC: u16 = 0x0001;
    const PRIVATE: u16 = 0x0002;
    const PROTECTED: u16 = 0x0004;
    const STATIC: u16 = 0x0008;
    const FINAL: u16 = 0x0010;
    const SUPER: u16 = 0x0020;
    const SYNCHRONIZED: u16 = 0x0020;
    const VOLATILE: u16 = 0x0040;
    const BRIDGE: u16 = 0x0040;
    const TRANSIENT: u16 = 0x0080;
    const VARARGS: u16 = 0x0080;
    const NATIVE: u16 = 0x0100;
    const INTERFACE: u16 = 0x0200;
    const ABSTRACT: u16 = 0x0400;
    const STRICT: u16 = 0x0800;
    const SYNTHETIC: u16 = 0x1000;
    const ANNOTATION: u16 = 0x2000;
    const ENUM: u16 = 0x4000;
    const MODULE: u16 = 0x8000;
};

/// 常量池标签类型
const ConstantTag = enum(u8) {
    utf8 = 1,
    integer = 3,
    float = 4,
    long = 5,
    double = 6,
    class = 7,
    string = 8,
    fieldref = 9,
    methodref = 10,
    interface_methodref = 11,
    name_and_type = 12,
    method_handle = 15,
    method_type = 16,
    dynamic = 17,
    invoke_dynamic = 18,
    module = 19,
    package = 20,
};

/// 常量池条目
pub const ConstantPoolEntry = union(ConstantTag) {
    utf8: []const u8,
    integer: i32,
    float: f32,
    long: i64,
    double: f64,
    class: u16,
    string: u16,
    fieldref: struct { class_index: u16, name_and_type_index: u16 },
    methodref: struct { class_index: u16, name_and_type_index: u16 },
    interface_methodref: struct { class_index: u16, name_and_type_index: u16 },
    name_and_type: struct { name_index: u16, descriptor_index: u16 },
    method_handle: struct { reference_kind: u8, reference_index: u16 },
    method_type: u16,
    dynamic: struct { bootstrap_method_attr_index: u16, name_and_type_index: u16 },
    invoke_dynamic: struct { bootstrap_method_attr_index: u16, name_and_type_index: u16 },
    module: u16,
    package: u16,
};

/// 字段信息
pub const FieldInfo = struct {
    access_flags: u16,
    name_index: u16,
    descriptor_index: u16,
    attributes_count: u16,
    attributes: []AttributeInfo,
};

/// 方法信息
pub const MethodInfo = struct {
    access_flags: u16,
    name_index: u16,
    descriptor_index: u16,
    attributes_count: u16,
    attributes: []AttributeInfo,
};

/// 属性信息
const AttributeInfo = struct {
    attribute_name_index: u16,
    attribute_length: u32,
    info: []u8,
};

/// Java Class 文件结构
pub const ClassFile = struct {
    magic: u32,
    minor_version: u16,
    major_version: u16,
    constant_pool_count: u16,
    constant_pool: []ConstantPoolEntry,
    access_flags: u16,
    this_class: u16,
    super_class: u16,
    interfaces_count: u16,
    interfaces: []u16,
    fields_count: u16,
    fields: []FieldInfo,
    methods_count: u16,
    methods: []MethodInfo,
    attributes_count: u16,
    attributes: []AttributeInfo,

    allocator: Allocator,

    /// 释放 ClassFile 占用的内存
    pub fn deinit(self: *ClassFile) void {
        // 释放常量池中的 UTF-8 字符串
        for (self.constant_pool) |entry| {
            if (entry == .utf8) {
                self.allocator.free(entry.utf8);
            }
        }

        // 释放各种数组
        self.allocator.free(self.constant_pool);
        self.allocator.free(self.interfaces);

        // 释放字段属性
        for (self.fields) |field| {
            for (field.attributes) |attr| {
                self.allocator.free(attr.info);
            }
            self.allocator.free(field.attributes);
        }
        self.allocator.free(self.fields);

        // 释放方法属性
        for (self.methods) |method| {
            for (method.attributes) |attr| {
                self.allocator.free(attr.info);
            }
            self.allocator.free(method.attributes);
        }
        self.allocator.free(self.methods);

        // 释放类属性
        for (self.attributes) |attr| {
            self.allocator.free(attr.info);
        }
        self.allocator.free(self.attributes);
    }
};

/// 字节码解析器
const BytecodeParser = struct {
    data: []const u8,
    pos: usize,
    allocator: Allocator,

    /// 创建新的字节码解析器
    fn init(data: []const u8, allocator: Allocator) BytecodeParser {
        return BytecodeParser{
            .data = data,
            .pos = 0,
            .allocator = allocator,
        };
    }

    /// 读取 u8 值
    fn readU8(self: *BytecodeParser) !u8 {
        if (self.pos >= self.data.len) {
            return error.UnexpectedEndOfFile;
        }
        const value = self.data[self.pos];
        self.pos += 1;
        return value;
    }

    /// 读取 u16 值 (大端序)
    fn readU16(self: *BytecodeParser) !u16 {
        if (self.pos + 2 > self.data.len) {
            return error.UnexpectedEndOfFile;
        }
        const value = std.mem.readInt(u16, self.data[self.pos .. self.pos + 2][0..2], .big);
        self.pos += 2;
        return value;
    }

    /// 读取 u32 值 (大端序)
    fn readU32(self: *BytecodeParser) !u32 {
        if (self.pos + 4 > self.data.len) {
            return error.UnexpectedEndOfFile;
        }
        const value = std.mem.readInt(u32, self.data[self.pos .. self.pos + 4][0..4], .big);
        self.pos += 4;
        return value;
    }

    /// 读取 i32 值 (大端序)
    fn readI32(self: *BytecodeParser) !i32 {
        return @bitCast(try self.readU32());
    }

    /// 读取 i64 值 (大端序)
    fn readI64(self: *BytecodeParser) !i64 {
        if (self.pos + 8 > self.data.len) {
            return error.UnexpectedEndOfFile;
        }
        const value = std.mem.readInt(i64, self.data[self.pos .. self.pos + 8][0..8], .big);
        self.pos += 8;
        return value;
    }

    /// 读取 f32 值 (大端序)
    fn readF32(self: *BytecodeParser) !f32 {
        const bits = try self.readU32();
        return @bitCast(bits);
    }

    /// 读取 f64 值 (大端序)
    fn readF64(self: *BytecodeParser) !f64 {
        if (self.pos + 8 > self.data.len) {
            return error.UnexpectedEndOfFile;
        }
        const bits = std.mem.readInt(u64, self.data[self.pos .. self.pos + 8][0..8], .big);
        self.pos += 8;
        return @bitCast(bits);
    }

    /// 读取指定长度的字节数组
    fn readBytes(self: *BytecodeParser, length: usize) ![]u8 {
        if (self.pos + length > self.data.len) {
            return error.UnexpectedEndOfFile;
        }
        const bytes = try self.allocator.alloc(u8, length);
        @memcpy(bytes, self.data[self.pos .. self.pos + length]);
        self.pos += length;
        return bytes;
    }

    /// 解析常量池条目
    fn parseConstantPoolEntry(self: *BytecodeParser) !ConstantPoolEntry {
        const tag = try self.readU8();

        return switch (@as(ConstantTag, @enumFromInt(tag))) {
            .utf8 => {
                const length = try self.readU16();
                const bytes = try self.readBytes(length);
                return ConstantPoolEntry{ .utf8 = bytes };
            },
            .integer => {
                const value = try self.readI32();
                return ConstantPoolEntry{ .integer = value };
            },
            .float => {
                const value = try self.readF32();
                return ConstantPoolEntry{ .float = value };
            },
            .long => {
                const value = try self.readI64();
                return ConstantPoolEntry{ .long = value };
            },
            .double => {
                const value = try self.readF64();
                return ConstantPoolEntry{ .double = value };
            },
            .class => {
                const name_index = try self.readU16();
                return ConstantPoolEntry{ .class = name_index };
            },
            .string => {
                const string_index = try self.readU16();
                return ConstantPoolEntry{ .string = string_index };
            },
            .fieldref => {
                const class_index = try self.readU16();
                const name_and_type_index = try self.readU16();
                return ConstantPoolEntry{ .fieldref = .{ .class_index = class_index, .name_and_type_index = name_and_type_index } };
            },
            .methodref => {
                const class_index = try self.readU16();
                const name_and_type_index = try self.readU16();
                return ConstantPoolEntry{ .methodref = .{ .class_index = class_index, .name_and_type_index = name_and_type_index } };
            },
            .interface_methodref => {
                const class_index = try self.readU16();
                const name_and_type_index = try self.readU16();
                return ConstantPoolEntry{ .interface_methodref = .{ .class_index = class_index, .name_and_type_index = name_and_type_index } };
            },
            .name_and_type => {
                const name_index = try self.readU16();
                const descriptor_index = try self.readU16();
                return ConstantPoolEntry{ .name_and_type = .{ .name_index = name_index, .descriptor_index = descriptor_index } };
            },
            .method_handle => {
                const reference_kind = try self.readU8();
                const reference_index = try self.readU16();
                return ConstantPoolEntry{ .method_handle = .{ .reference_kind = reference_kind, .reference_index = reference_index } };
            },
            .method_type => {
                const descriptor_index = try self.readU16();
                return ConstantPoolEntry{ .method_type = descriptor_index };
            },
            .dynamic => {
                const bootstrap_method_attr_index = try self.readU16();
                const name_and_type_index = try self.readU16();
                return ConstantPoolEntry{ .dynamic = .{ .bootstrap_method_attr_index = bootstrap_method_attr_index, .name_and_type_index = name_and_type_index } };
            },
            .invoke_dynamic => {
                const bootstrap_method_attr_index = try self.readU16();
                const name_and_type_index = try self.readU16();
                return ConstantPoolEntry{ .invoke_dynamic = .{ .bootstrap_method_attr_index = bootstrap_method_attr_index, .name_and_type_index = name_and_type_index } };
            },
            .module => {
                const name_index = try self.readU16();
                return ConstantPoolEntry{ .module = name_index };
            },
            .package => {
                const name_index = try self.readU16();
                return ConstantPoolEntry{ .package = name_index };
            },
        };
    }

    /// 解析属性信息
    fn parseAttribute(self: *BytecodeParser) !AttributeInfo {
        const attribute_name_index = try self.readU16();
        const attribute_length = try self.readU32();
        const info = try self.readBytes(attribute_length);

        return AttributeInfo{
            .attribute_name_index = attribute_name_index,
            .attribute_length = attribute_length,
            .info = info,
        };
    }

    /// 解析字段信息
    fn parseField(self: *BytecodeParser) !FieldInfo {
        const access_flags = try self.readU16();
        const name_index = try self.readU16();
        const descriptor_index = try self.readU16();
        const attributes_count = try self.readU16();

        const attributes = try self.allocator.alloc(AttributeInfo, attributes_count);
        for (attributes) |*attr| {
            attr.* = try self.parseAttribute();
        }

        return FieldInfo{
            .access_flags = access_flags,
            .name_index = name_index,
            .descriptor_index = descriptor_index,
            .attributes_count = attributes_count,
            .attributes = attributes,
        };
    }

    /// 解析方法信息
    fn parseMethod(self: *BytecodeParser) !MethodInfo {
        const access_flags = try self.readU16();
        const name_index = try self.readU16();
        const descriptor_index = try self.readU16();
        const attributes_count = try self.readU16();

        const attributes = try self.allocator.alloc(AttributeInfo, attributes_count);
        for (attributes) |*attr| {
            attr.* = try self.parseAttribute();
        }

        return MethodInfo{
            .access_flags = access_flags,
            .name_index = name_index,
            .descriptor_index = descriptor_index,
            .attributes_count = attributes_count,
            .attributes = attributes,
        };
    }

    /// 解析完整的 Class 文件
    fn parseClassFile(self: *BytecodeParser) !ClassFile {
        // 验证魔数
        const magic = try self.readU32();
        if (magic != JAVA_MAGIC) {
            return error.InvalidMagicNumber;
        }

        // 读取版本信息
        const minor_version = try self.readU16();
        const major_version = try self.readU16();

        // 验证版本
        if (major_version < MIN_MAJOR_VERSION or major_version > MAX_MAJOR_VERSION) {
            return error.UnsupportedClassFileVersion;
        }

        // 解析常量池
        const constant_pool_count = try self.readU16();
        const constant_pool = try self.allocator.alloc(ConstantPoolEntry, constant_pool_count - 1);

        var i: usize = 0;
        while (i < constant_pool_count - 1) {
            constant_pool[i] = try self.parseConstantPoolEntry();

            // Long 和 Double 常量占用两个常量池位置
            if (constant_pool[i] == .long or constant_pool[i] == .double) {
                i += 1;
                if (i < constant_pool_count - 1) {
                    // 填充一个占位符
                    constant_pool[i] = ConstantPoolEntry{ .integer = 0 };
                }
            }
            i += 1;
        }

        // 读取类访问标志和索引
        const access_flags = try self.readU16();
        const this_class = try self.readU16();
        const super_class = try self.readU16();

        // 解析接口
        const interfaces_count = try self.readU16();
        const interfaces = try self.allocator.alloc(u16, interfaces_count);
        for (interfaces) |*interface| {
            interface.* = try self.readU16();
        }

        // 解析字段
        const fields_count = try self.readU16();
        const fields = try self.allocator.alloc(FieldInfo, fields_count);
        for (fields) |*field| {
            field.* = try self.parseField();
        }

        // 解析方法
        const methods_count = try self.readU16();
        const methods = try self.allocator.alloc(MethodInfo, methods_count);
        for (methods) |*method| {
            method.* = try self.parseMethod();
        }

        // 解析类属性
        const attributes_count = try self.readU16();
        const attributes = try self.allocator.alloc(AttributeInfo, attributes_count);
        for (attributes) |*attr| {
            attr.* = try self.parseAttribute();
        }

        return ClassFile{
            .magic = magic,
            .minor_version = minor_version,
            .major_version = major_version,
            .constant_pool_count = constant_pool_count,
            .constant_pool = constant_pool,
            .access_flags = access_flags,
            .this_class = this_class,
            .super_class = super_class,
            .interfaces_count = interfaces_count,
            .interfaces = interfaces,
            .fields_count = fields_count,
            .fields = fields,
            .methods_count = methods_count,
            .methods = methods,
            .attributes_count = attributes_count,
            .attributes = attributes,
            .allocator = self.allocator,
        };
    }
};

/// 解析 Java Class 文件字节码
pub fn parseClassFile(data: []const u8, allocator: Allocator) !ClassFile {
    var parser = BytecodeParser.init(data, allocator);
    return parser.parseClassFile();
}

/// 验证访问标志是否有效
fn isValidAccessFlags(flags: u16, is_interface: bool) bool {
    // 接口类的特殊验证
    if (is_interface) {
        // 接口必须是 abstract 和 interface
        if ((flags & AccessFlags.ABSTRACT) == 0 or (flags & AccessFlags.INTERFACE) == 0) {
            return false;
        }
        // 接口不能是 final, super, enum
        if ((flags & AccessFlags.FINAL) != 0 or
            (flags & AccessFlags.SUPER) != 0 or
            (flags & AccessFlags.ENUM) != 0)
        {
            return false;
        }
    }

    // 不能同时是 final 和 abstract
    if ((flags & AccessFlags.FINAL) != 0 and (flags & AccessFlags.ABSTRACT) != 0) {
        return false;
    }

    return true;
}

// 导出公共接口
const exports = struct {
    const ClassFile = @This().ClassFile;
    const ConstantPoolEntry = @This().ConstantPoolEntry;
    const FieldInfo = @This().FieldInfo;
    const MethodInfo = @This().MethodInfo;
    const AttributeInfo = @This().AttributeInfo;
    const AccessFlags = @This().AccessFlags;
    const parseClassFile = @This().parseClassFile;
    const isValidAccessFlags = @This().isValidAccessFlags;
};

test "字节码解析器基础功能测试" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // 创建一个简单的 Class 文件数据用于测试
    const test_data = [_]u8{
        0xCA, 0xFE, 0xBA, 0xBE, // 魔数
        0x00, 0x00, // minor_version
        0x00, 0x34, // major_version (Java 8)
        0x00, 0x01, // constant_pool_count
        0x00, 0x21, // access_flags (PUBLIC | SUPER)
        0x00, 0x00, // this_class
        0x00, 0x00, // super_class
        0x00, 0x00, // interfaces_count
        0x00, 0x00, // fields_count
        0x00, 0x00, // methods_count
        0x00, 0x00, // attributes_count
    };

    var parser = BytecodeParser.init(&test_data, allocator);

    // 测试基础读取功能
    try testing.expectEqual(@as(u32, JAVA_MAGIC), try parser.readU32());
    try testing.expectEqual(@as(u16, 0), try parser.readU16());
    try testing.expectEqual(@as(u16, 52), try parser.readU16());
}

test "访问标志验证测试" {
    const testing = std.testing;

    // 测试普通类的访问标志
    try testing.expect(isValidAccessFlags(AccessFlags.PUBLIC | AccessFlags.SUPER, false));
    try testing.expect(!isValidAccessFlags(AccessFlags.FINAL | AccessFlags.ABSTRACT, false));

    // 测试接口的访问标志
    try testing.expect(isValidAccessFlags(AccessFlags.PUBLIC | AccessFlags.INTERFACE | AccessFlags.ABSTRACT, true));
    try testing.expect(!isValidAccessFlags(AccessFlags.PUBLIC | AccessFlags.FINAL | AccessFlags.INTERFACE | AccessFlags.ABSTRACT, true));
}
