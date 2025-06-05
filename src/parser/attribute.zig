//! Java Class 文件属性解析器
//! 处理各种属性类型，如 Code、ConstantValue、Exceptions、Signature 等

const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const testing = std.testing;

// 导入相关模块
const bytecode = @import("bytecode.zig");
const ConstantPoolManager = @import("constant_pool.zig").ConstantPoolManager;
const ClassReader = @import("class_reader.zig").ClassReader;

/// 属性类型枚举
pub const AttributeType = enum {
    ConstantValue,
    Code,
    StackMapTable,
    Exceptions,
    InnerClasses,
    EnclosingMethod,
    Synthetic,
    Signature,
    SourceFile,
    SourceDebugExtension,
    LineNumberTable,
    LocalVariableTable,
    LocalVariableTypeTable,
    Deprecated,
    RuntimeVisibleAnnotations,
    RuntimeInvisibleAnnotations,
    RuntimeVisibleParameterAnnotations,
    RuntimeInvisibleParameterAnnotations,
    RuntimeVisibleTypeAnnotations,
    RuntimeInvisibleTypeAnnotations,
    AnnotationDefault,
    BootstrapMethods,
    MethodParameters,
    Module,
    ModulePackages,
    ModuleMainClass,
    NestHost,
    NestMembers,
    Record,
    PermittedSubclasses,
    Unknown,
};

/// 属性信息基础结构
pub const AttributeInfo = struct {
    attribute_name_index: u16,
    attribute_length: u32,
    info: []u8,
    attribute_type: AttributeType,

    /// 释放属性信息资源
    pub fn deinit(self: *AttributeInfo, allocator: Allocator) void {
        allocator.free(self.info);
    }
};

/// ConstantValue 属性
pub const ConstantValueAttribute = struct {
    constantvalue_index: u16,
};

/// 异常表条目
pub const ExceptionTableEntry = struct {
    start_pc: u16,
    end_pc: u16,
    handler_pc: u16,
    catch_type: u16, // 0 表示 finally
};

/// Code 属性
pub const CodeAttribute = struct {
    max_stack: u16,
    max_locals: u16,
    code_length: u32,
    code: []u8,
    exception_table_length: u16,
    exception_table: []ExceptionTableEntry,
    attributes_count: u16,
    attributes: []AttributeInfo,

    /// 释放 Code 属性资源
    pub fn deinit(self: *CodeAttribute, allocator: Allocator) void {
        allocator.free(self.code);
        allocator.free(self.exception_table);

        for (self.attributes) |*attr| {
            attr.deinit(allocator);
        }
        allocator.free(self.attributes);
    }
};

/// 行号表条目
pub const LineNumberTableEntry = struct {
    start_pc: u16,
    line_number: u16,
};

/// LineNumberTable 属性
pub const LineNumberTableAttribute = struct {
    line_number_table_length: u16,
    line_number_table: []LineNumberTableEntry,

    /// 释放行号表资源
    pub fn deinit(self: *LineNumberTableAttribute, allocator: Allocator) void {
        allocator.free(self.line_number_table);
    }
};

/// 局部变量表条目
pub const LocalVariableTableEntry = struct {
    start_pc: u16,
    length: u16,
    name_index: u16,
    descriptor_index: u16,
    index: u16,
};

/// LocalVariableTable 属性
pub const LocalVariableTableAttribute = struct {
    local_variable_table_length: u16,
    local_variable_table: []LocalVariableTableEntry,

    /// 释放局部变量表资源
    pub fn deinit(self: *LocalVariableTableAttribute, allocator: Allocator) void {
        allocator.free(self.local_variable_table);
    }
};

/// Exceptions 属性
pub const ExceptionsAttribute = struct {
    number_of_exceptions: u16,
    exception_index_table: []u16,

    /// 释放异常表资源
    pub fn deinit(self: *ExceptionsAttribute, allocator: Allocator) void {
        allocator.free(self.exception_index_table);
    }
};

/// InnerClass 信息
pub const InnerClassInfo = struct {
    inner_class_info_index: u16,
    outer_class_info_index: u16,
    inner_name_index: u16,
    inner_class_access_flags: u16,
};

/// InnerClasses 属性
pub const InnerClassesAttribute = struct {
    number_of_classes: u16,
    classes: []InnerClassInfo,

    /// 释放内部类信息资源
    pub fn deinit(self: *InnerClassesAttribute, allocator: Allocator) void {
        allocator.free(self.classes);
    }
};

/// EnclosingMethod 属性
pub const EnclosingMethodAttribute = struct {
    class_index: u16,
    method_index: u16,
};

/// Signature 属性
pub const SignatureAttribute = struct {
    signature_index: u16,
};

/// SourceFile 属性
pub const SourceFileAttribute = struct {
    sourcefile_index: u16,
};

/// 属性解析器
pub const AttributeParser = struct {
    allocator: Allocator,
    constant_pool: *const ConstantPoolManager,

    /// 初始化属性解析器
    pub fn init(allocator: Allocator, constant_pool: *const ConstantPoolManager) AttributeParser {
        return AttributeParser{
            .allocator = allocator,
            .constant_pool = constant_pool,
        };
    }

    /// 解析属性类型
    pub fn parseAttributeType(self: *const AttributeParser, name_index: u16) AttributeType {
        const name = self.constant_pool.getUtf8String(name_index) catch return .Unknown;

        if (std.mem.eql(u8, name, "ConstantValue")) return .ConstantValue;
        if (std.mem.eql(u8, name, "Code")) return .Code;
        if (std.mem.eql(u8, name, "StackMapTable")) return .StackMapTable;
        if (std.mem.eql(u8, name, "Exceptions")) return .Exceptions;
        if (std.mem.eql(u8, name, "InnerClasses")) return .InnerClasses;
        if (std.mem.eql(u8, name, "EnclosingMethod")) return .EnclosingMethod;
        if (std.mem.eql(u8, name, "Synthetic")) return .Synthetic;
        if (std.mem.eql(u8, name, "Signature")) return .Signature;
        if (std.mem.eql(u8, name, "SourceFile")) return .SourceFile;
        if (std.mem.eql(u8, name, "SourceDebugExtension")) return .SourceDebugExtension;
        if (std.mem.eql(u8, name, "LineNumberTable")) return .LineNumberTable;
        if (std.mem.eql(u8, name, "LocalVariableTable")) return .LocalVariableTable;
        if (std.mem.eql(u8, name, "LocalVariableTypeTable")) return .LocalVariableTypeTable;
        if (std.mem.eql(u8, name, "Deprecated")) return .Deprecated;
        if (std.mem.eql(u8, name, "RuntimeVisibleAnnotations")) return .RuntimeVisibleAnnotations;
        if (std.mem.eql(u8, name, "RuntimeInvisibleAnnotations")) return .RuntimeInvisibleAnnotations;
        if (std.mem.eql(u8, name, "RuntimeVisibleParameterAnnotations")) return .RuntimeVisibleParameterAnnotations;
        if (std.mem.eql(u8, name, "RuntimeInvisibleParameterAnnotations")) return .RuntimeInvisibleParameterAnnotations;
        if (std.mem.eql(u8, name, "RuntimeVisibleTypeAnnotations")) return .RuntimeVisibleTypeAnnotations;
        if (std.mem.eql(u8, name, "RuntimeInvisibleTypeAnnotations")) return .RuntimeInvisibleTypeAnnotations;
        if (std.mem.eql(u8, name, "AnnotationDefault")) return .AnnotationDefault;
        if (std.mem.eql(u8, name, "BootstrapMethods")) return .BootstrapMethods;
        if (std.mem.eql(u8, name, "MethodParameters")) return .MethodParameters;
        if (std.mem.eql(u8, name, "Module")) return .Module;
        if (std.mem.eql(u8, name, "ModulePackages")) return .ModulePackages;
        if (std.mem.eql(u8, name, "ModuleMainClass")) return .ModuleMainClass;
        if (std.mem.eql(u8, name, "NestHost")) return .NestHost;
        if (std.mem.eql(u8, name, "NestMembers")) return .NestMembers;
        if (std.mem.eql(u8, name, "Record")) return .Record;
        if (std.mem.eql(u8, name, "PermittedSubclasses")) return .PermittedSubclasses;

        return .Unknown;
    }

    /// 解析属性信息
    pub fn parseAttribute(self: *const AttributeParser, reader: *ClassReader) !AttributeInfo {
        const name_index = try reader.readU16();
        const length = try reader.readU32();

        const info = try self.allocator.alloc(u8, length);
        errdefer self.allocator.free(info);

        _ = try reader.readBytes(info);

        const attr_type = self.parseAttributeType(name_index);

        return AttributeInfo{
            .attribute_name_index = name_index,
            .attribute_length = length,
            .info = info,
            .attribute_type = attr_type,
        };
    }

    /// 解析 ConstantValue 属性
    pub fn parseConstantValue(_: *const AttributeParser, attr: *const AttributeInfo) !ConstantValueAttribute {
        if (attr.info.len != 2) {
            return error.InvalidConstantValueAttribute;
        }

        var reader = ClassReader.initFromBytes(attr.info);
        const constantvalue_index = try reader.readU16();

        return ConstantValueAttribute{
            .constantvalue_index = constantvalue_index,
        };
    }

    /// 解析 Code 属性
    pub fn parseCode(self: *const AttributeParser, attr: *const AttributeInfo) !CodeAttribute {
        var reader = ClassReader.initFromBytes(attr.info);

        const max_stack = try reader.readU16();
        const max_locals = try reader.readU16();
        const code_length = try reader.readU32();

        const code = try self.allocator.alloc(u8, code_length);
        errdefer self.allocator.free(code);
        _ = try reader.readBytes(code);

        const exception_table_length = try reader.readU16();
        const exception_table = try self.allocator.alloc(ExceptionTableEntry, exception_table_length);
        errdefer self.allocator.free(exception_table);

        for (exception_table) |*entry| {
            entry.start_pc = try reader.readU16();
            entry.end_pc = try reader.readU16();
            entry.handler_pc = try reader.readU16();
            entry.catch_type = try reader.readU16();
        }

        const attributes_count = try reader.readU16();
        const attributes = try self.allocator.alloc(AttributeInfo, attributes_count);
        errdefer {
            for (attributes) |*sub_attr| {
                sub_attr.deinit(self.allocator);
            }
            self.allocator.free(attributes);
        }

        for (attributes) |*sub_attr| {
            sub_attr.* = try self.parseAttribute(&reader);
        }

        return CodeAttribute{
            .max_stack = max_stack,
            .max_locals = max_locals,
            .code_length = code_length,
            .code = code,
            .exception_table_length = exception_table_length,
            .exception_table = exception_table,
            .attributes_count = attributes_count,
            .attributes = attributes,
        };
    }

    /// 解析 LineNumberTable 属性
    pub fn parseLineNumberTable(self: *const AttributeParser, attr: *const AttributeInfo) !LineNumberTableAttribute {
        var reader = ClassReader.initFromBytes(attr.info);

        const table_length = try reader.readU16();
        const table = try self.allocator.alloc(LineNumberTableEntry, table_length);
        errdefer self.allocator.free(table);

        for (table) |*entry| {
            entry.start_pc = try reader.readU16();
            entry.line_number = try reader.readU16();
        }

        return LineNumberTableAttribute{
            .line_number_table_length = table_length,
            .line_number_table = table,
        };
    }

    /// 解析 LocalVariableTable 属性
    pub fn parseLocalVariableTable(self: *const AttributeParser, attr: *const AttributeInfo) !LocalVariableTableAttribute {
        var reader = ClassReader.initFromBytes(attr.info);

        const table_length = try reader.readU16();
        const table = try self.allocator.alloc(LocalVariableTableEntry, table_length);
        errdefer self.allocator.free(table);

        for (table) |*entry| {
            entry.start_pc = try reader.readU16();
            entry.length = try reader.readU16();
            entry.name_index = try reader.readU16();
            entry.descriptor_index = try reader.readU16();
            entry.index = try reader.readU16();
        }

        return LocalVariableTableAttribute{
            .local_variable_table_length = table_length,
            .local_variable_table = table,
        };
    }

    /// 解析 Exceptions 属性
    pub fn parseExceptions(self: *const AttributeParser, attr: *const AttributeInfo) !ExceptionsAttribute {
        var reader = ClassReader.initFromBytes(attr.info);

        const number_of_exceptions = try reader.readU16();
        const exception_index_table = try self.allocator.alloc(u16, number_of_exceptions);
        errdefer self.allocator.free(exception_index_table);

        for (exception_index_table) |*index| {
            index.* = try reader.readU16();
        }

        return ExceptionsAttribute{
            .number_of_exceptions = number_of_exceptions,
            .exception_index_table = exception_index_table,
        };
    }

    /// 解析 InnerClasses 属性
    pub fn parseInnerClasses(self: *const AttributeParser, attr: *const AttributeInfo) !InnerClassesAttribute {
        var reader = ClassReader.initFromBytes(attr.info);

        const number_of_classes = try reader.readU16();
        const classes = try self.allocator.alloc(InnerClassInfo, number_of_classes);
        errdefer self.allocator.free(classes);

        for (classes) |*class_info| {
            class_info.inner_class_info_index = try reader.readU16();
            class_info.outer_class_info_index = try reader.readU16();
            class_info.inner_name_index = try reader.readU16();
            class_info.inner_class_access_flags = try reader.readU16();
        }

        return InnerClassesAttribute{
            .number_of_classes = number_of_classes,
            .classes = classes,
        };
    }

    /// 解析 EnclosingMethod 属性
    pub fn parseEnclosingMethod(_: *const AttributeParser, attr: *const AttributeInfo) !EnclosingMethodAttribute {
        if (attr.info.len != 4) {
            return error.InvalidEnclosingMethodAttribute;
        }

        var reader = ClassReader.initFromBytes(attr.info);
        const class_index = try reader.readU16();
        const method_index = try reader.readU16();

        return EnclosingMethodAttribute{
            .class_index = class_index,
            .method_index = method_index,
        };
    }

    /// 解析 Signature 属性
    pub fn parseSignature(_: *const AttributeParser, attr: *const AttributeInfo) !SignatureAttribute {
        if (attr.info.len != 2) {
            return error.InvalidSignatureAttribute;
        }

        var reader = ClassReader.initFromBytes(attr.info);
        const signature_index = try reader.readU16();

        return SignatureAttribute{
            .signature_index = signature_index,
        };
    }

    /// 解析 SourceFile 属性
    pub fn parseSourceFile(_: *const AttributeParser, attr: *const AttributeInfo) !SourceFileAttribute {
        if (attr.info.len != 2) {
            return error.InvalidSourceFileAttribute;
        }

        var reader = ClassReader.initFromBytes(attr.info);
        const sourcefile_index = try reader.readU16();

        return SourceFileAttribute{
            .sourcefile_index = sourcefile_index,
        };
    }

    /// 获取属性名称
    pub fn getAttributeName(self: *const AttributeParser, attr: *const AttributeInfo) ![]const u8 {
        return self.constant_pool.getUtf8String(attr.attribute_name_index);
    }

    /// 检查是否为已知属性类型
    pub fn isKnownAttribute(self: *const AttributeParser, name_index: u16) bool {
        return self.parseAttributeType(name_index) != .Unknown;
    }
};

// 基础测试
test "AttributeParser basic functionality" {
    const allocator = testing.allocator;

    // 创建模拟常量池
    var constant_pool = ConstantPoolManager.init(&[_]bytecode.ConstantPoolEntry{}, allocator) catch unreachable;
    defer constant_pool.deinit();

    // 创建属性解析器
    const parser = AttributeParser.init(allocator, &constant_pool);

    // 测试属性类型解析
    const attr_type = parser.parseAttributeType(1);
    try testing.expect(attr_type == .Unknown); // 因为常量池为空
}

test "AttributeType enum" {
    try testing.expect(@intFromEnum(AttributeType.ConstantValue) == 0);
    try testing.expect(@intFromEnum(AttributeType.Code) == 1);
    try testing.expect(@intFromEnum(AttributeType.Unknown) == @intFromEnum(AttributeType.PermittedSubclasses) + 1);
}
