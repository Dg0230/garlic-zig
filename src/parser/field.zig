//! Java 字段解析器
//! 负责解析 Java 类中的字段信息，包括字段描述符、访问标志和属性

const std = @import("std");
const bytecode = @import("bytecode.zig");
const constant_pool = @import("constant_pool.zig");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;

/// Java 值类型
const JavaValue = union(enum) {
    int: i32,
    long: i64,
    float: f32,
    double: f64,
    reference: ?*anyopaque,
};

/// Java 基本类型
const JavaType = enum {
    byte,
    char,
    double,
    float,
    int,
    long,
    short,
    boolean,
    void,
    object,
    array,

    /// 从字段描述符字符获取类型
    fn fromDescriptor(descriptor_char: u8) JavaType {
        return switch (descriptor_char) {
            'B' => .byte,
            'C' => .char,
            'D' => .double,
            'F' => .float,
            'I' => .int,
            'J' => .long,
            'S' => .short,
            'Z' => .boolean,
            'V' => .void,
            'L' => .object,
            '[' => .array,
            else => .object, // 默认为对象类型
        };
    }

    /// 获取类型的大小（在栈中占用的槽位数）
    fn getSize(self: JavaType) u8 {
        return switch (self) {
            .long, .double => 2,
            else => 1,
        };
    }

    /// 检查是否为基本类型
    fn isPrimitive(self: JavaType) bool {
        return switch (self) {
            .byte, .char, .double, .float, .int, .long, .short, .boolean => true,
            else => false,
        };
    }

    /// 获取类型的默认值
    fn getDefaultValue(self: JavaType) JavaValue {
        return switch (self) {
            .byte, .char, .short, .int => JavaValue{ .int = 0 },
            .long => JavaValue{ .long = 0 },
            .float => JavaValue{ .float = 0.0 },
            .double => JavaValue{ .double = 0.0 },
            .boolean => JavaValue{ .int = 0 }, // false
            else => JavaValue{ .reference = null },
        };
    }
};

/// 字段描述符信息
const FieldDescriptor = struct {
    field_type: JavaType,
    class_name: ?[]const u8, // 对象类型的类名
    array_dimensions: u8, // 数组维度
    component_type: ?JavaType, // 数组元素类型

    /// 创建基本类型描述符
    fn primitive(field_type: JavaType) FieldDescriptor {
        return FieldDescriptor{
            .field_type = field_type,
            .class_name = null,
            .array_dimensions = 0,
            .component_type = null,
        };
    }

    /// 创建对象类型描述符
    fn object(class_name: []const u8) FieldDescriptor {
        return FieldDescriptor{
            .field_type = .object,
            .class_name = class_name,
            .array_dimensions = 0,
            .component_type = null,
        };
    }

    /// 创建数组类型描述符
    fn array(dimensions: u8, component_type: JavaType, class_name: ?[]const u8) FieldDescriptor {
        return FieldDescriptor{
            .field_type = .array,
            .class_name = class_name,
            .array_dimensions = dimensions,
            .component_type = component_type,
        };
    }

    /// 检查是否为数组类型
    fn isArray(self: *const FieldDescriptor) bool {
        return self.field_type == .array;
    }

    /// 检查是否为对象类型
    fn isObject(self: *const FieldDescriptor) bool {
        return self.field_type == .object;
    }

    /// 检查是否为基本类型
    fn isPrimitive(self: *const FieldDescriptor) bool {
        return self.field_type.isPrimitive();
    }

    /// 获取字段大小
    fn getSize(self: *const FieldDescriptor) u8 {
        if (self.isArray() or self.isObject()) {
            return 1; // 引用类型占用1个槽位
        }
        return self.field_type.getSize();
    }

    /// 获取默认值
    fn getDefaultValue(self: *const FieldDescriptor) JavaValue {
        if (self.isArray() or self.isObject()) {
            return JavaValue{ .reference = null };
        }
        return self.field_type.getDefaultValue();
    }

    /// 释放内存
    fn deinit(self: *const FieldDescriptor, allocator: Allocator) void {
        if (self.class_name) |name| {
            allocator.free(name);
        }
    }
};

/// 字段信息
const FieldInfo = struct {
    access_flags: u16,
    name_index: u16,
    descriptor_index: u16,
    attributes_count: u16,
    attributes: []bytecode.AttributeInfo,

    // 解析后的信息
    name: ?[]const u8,
    descriptor: ?FieldDescriptor,
    constant_value: ?JavaValue, // ConstantValue 属性
    is_synthetic: bool,
    is_deprecated: bool,
    signature: ?[]const u8, // 泛型签名
    annotations: ArrayList(bytecode.AnnotationInfo),

    allocator: Allocator,

    /// 创建字段信息
    fn init(allocator: Allocator) FieldInfo {
        return FieldInfo{
            .access_flags = 0,
            .name_index = 0,
            .descriptor_index = 0,
            .attributes_count = 0,
            .attributes = &[_]bytecode.AttributeInfo{},
            .name = null,
            .descriptor = null,
            .constant_value = null,
            .is_synthetic = false,
            .is_deprecated = false,
            .signature = null,
            .annotations = ArrayList(bytecode.AnnotationInfo).init(allocator),
            .allocator = allocator,
        };
    }

    /// 释放资源
    fn deinit(self: *FieldInfo) void {
        if (self.name) |name| {
            self.allocator.free(name);
        }
        if (self.signature) |signature| {
            self.allocator.free(signature);
        }

        // 释放属性
        for (self.attributes) |*attr| {
            attr.deinit(self.allocator);
        }
        if (self.attributes.len > 0) {
            self.allocator.free(self.attributes);
        }

        // 释放注解
        for (self.annotations.items) |*annotation| {
            annotation.deinit(self.allocator);
        }
        self.annotations.deinit();
    }

    /// 检查访问标志
    fn isPublic(self: *const FieldInfo) bool {
        return (self.access_flags & bytecode.AccessFlags.PUBLIC) != 0;
    }

    fn isPrivate(self: *const FieldInfo) bool {
        return (self.access_flags & bytecode.AccessFlags.PRIVATE) != 0;
    }

    fn isProtected(self: *const FieldInfo) bool {
        return (self.access_flags & bytecode.AccessFlags.PROTECTED) != 0;
    }

    fn isStatic(self: *const FieldInfo) bool {
        return (self.access_flags & bytecode.AccessFlags.STATIC) != 0;
    }

    fn isFinal(self: *const FieldInfo) bool {
        return (self.access_flags & bytecode.AccessFlags.FINAL) != 0;
    }

    fn isVolatile(self: *const FieldInfo) bool {
        return (self.access_flags & bytecode.AccessFlags.VOLATILE) != 0;
    }

    fn isTransient(self: *const FieldInfo) bool {
        return (self.access_flags & bytecode.AccessFlags.TRANSIENT) != 0;
    }

    fn isSynthetic(self: *const FieldInfo) bool {
        return self.is_synthetic;
    }

    fn isEnum(self: *const FieldInfo) bool {
        return (self.access_flags & bytecode.AccessFlags.ENUM) != 0;
    }

    /// 获取可见性级别
    fn getVisibility(self: *const FieldInfo) bytecode.Visibility {
        if (self.isPublic()) return .public;
        if (self.isProtected()) return .protected;
        if (self.isPrivate()) return .private;
        return .package_private;
    }

    /// 检查是否有常量值
    fn hasConstantValue(self: *const FieldInfo) bool {
        return self.constant_value != null;
    }

    /// 获取字段的完整名称（包含类名）
    fn getFullName(self: *const FieldInfo, class_name: []const u8, allocator: Allocator) ![]u8 {
        if (self.name) |name| {
            return std.fmt.allocPrint(allocator, "{s}.{s}", .{ class_name, name });
        }
        return error.FieldNameNotResolved;
    }
};

/// 字段解析器
const FieldParser = struct {
    allocator: Allocator,
    constant_pool: []const bytecode.ConstantPoolEntry,
    cp_manager: *constant_pool.ConstantPoolManager,

    /// 创建字段解析器
    fn init(allocator: Allocator, constant_pool_entries: []const bytecode.ConstantPoolEntry, cp_manager: *constant_pool.ConstantPoolManager) FieldParser {
        return FieldParser{
            .allocator = allocator,
            .constant_pool = constant_pool_entries,
            .cp_manager = cp_manager,
        };
    }

    /// 解析字段描述符
    fn parseFieldDescriptor(self: *FieldParser, descriptor: []const u8) !FieldDescriptor {
        if (descriptor.len == 0) {
            return error.EmptyFieldDescriptor;
        }

        var pos: usize = 0;
        return self.parseFieldDescriptorAt(descriptor, &pos);
    }

    /// 在指定位置解析字段描述符
    fn parseFieldDescriptorAt(self: *FieldParser, descriptor: []const u8, pos: *usize) !FieldDescriptor {
        if (pos.* >= descriptor.len) {
            return error.UnexpectedEndOfDescriptor;
        }

        const first_char = descriptor[pos.*];
        pos.* += 1;

        switch (first_char) {
            'B', 'C', 'D', 'F', 'I', 'J', 'S', 'Z' => {
                // 基本类型
                return FieldDescriptor.primitive(JavaType.fromDescriptor(first_char));
            },
            'L' => {
                // 对象类型: Lcom/example/ClassName;
                const start = pos.*;
                while (pos.* < descriptor.len and descriptor[pos.*] != ';') {
                    pos.* += 1;
                }

                if (pos.* >= descriptor.len) {
                    return error.UnterminatedObjectType;
                }

                const class_name = descriptor[start..pos.*];
                pos.* += 1; // 跳过 ';'

                const owned_class_name = try self.allocator.dupe(u8, class_name);
                return FieldDescriptor.object(owned_class_name);
            },
            '[' => {
                // 数组类型
                var dimensions: u8 = 1;

                // 计算数组维度
                while (pos.* < descriptor.len and descriptor[pos.*] == '[') {
                    dimensions += 1;
                    pos.* += 1;
                }

                if (dimensions > 255) {
                    return error.TooManyArrayDimensions;
                }

                // 解析组件类型
                const component_descriptor = try self.parseFieldDescriptorAt(descriptor, pos);

                return FieldDescriptor.array(
                    dimensions,
                    component_descriptor.field_type,
                    component_descriptor.class_name,
                );
            },
            else => {
                return error.InvalidFieldDescriptor;
            },
        }
    }

    /// 解析字段信息
    fn parseField(self: *FieldParser, field_info: *bytecode.FieldInfo) !FieldInfo {
        var parsed_field = FieldInfo.init(self.allocator);

        // 复制基本信息
        parsed_field.access_flags = field_info.access_flags;
        parsed_field.name_index = field_info.name_index;
        parsed_field.descriptor_index = field_info.descriptor_index;
        parsed_field.attributes_count = field_info.attributes_count;
        parsed_field.attributes = field_info.attributes;

        // 解析字段名
        if (try self.cp_manager.getUtf8String(field_info.name_index)) |name| {
            parsed_field.name = try self.allocator.dupe(u8, name);
        }

        // 解析字段描述符
        if (try self.cp_manager.getUtf8String(field_info.descriptor_index)) |descriptor_str| {
            parsed_field.descriptor = try self.parseFieldDescriptor(descriptor_str);
        }

        // 解析属性
        try self.parseFieldAttributes(&parsed_field);

        return parsed_field;
    }

    /// 解析字段属性
    fn parseFieldAttributes(self: *FieldParser, field: *FieldInfo) !void {
        for (field.attributes) |*attr| {
            const attr_name = try self.cp_manager.getUtf8String(attr.attribute_name_index) orelse continue;

            if (std.mem.eql(u8, attr_name, "ConstantValue")) {
                try self.parseConstantValueAttribute(field, attr);
            } else if (std.mem.eql(u8, attr_name, "Synthetic")) {
                field.is_synthetic = true;
            } else if (std.mem.eql(u8, attr_name, "Deprecated")) {
                field.is_deprecated = true;
            } else if (std.mem.eql(u8, attr_name, "Signature")) {
                try self.parseSignatureAttribute(field, attr);
            } else if (std.mem.eql(u8, attr_name, "RuntimeVisibleAnnotations")) {
                try self.parseAnnotationsAttribute(field, attr, true);
            } else if (std.mem.eql(u8, attr_name, "RuntimeInvisibleAnnotations")) {
                try self.parseAnnotationsAttribute(field, attr, false);
            }
        }
    }

    /// 解析 ConstantValue 属性
    fn parseConstantValueAttribute(self: *FieldParser, field: *FieldInfo, attr: *const bytecode.AttributeInfo) !void {
        if (attr.info.len != 2) {
            return error.InvalidConstantValueAttribute;
        }

        const constant_index = std.mem.readInt(u16, attr.info[0..2][0..2], .big);

        // 根据字段类型获取常量值
        if (field.descriptor) |descriptor| {
            field.constant_value = try self.getConstantValue(constant_index, descriptor.field_type);
        }
    }

    /// 解析 Signature 属性
    fn parseSignatureAttribute(self: *FieldParser, field: *FieldInfo, attr: *const bytecode.AttributeInfo) !void {
        if (attr.info.len != 2) {
            return error.InvalidSignatureAttribute;
        }

        const signature_index = std.mem.readInt(u16, attr.info[0..2][0..2], .big);
        if (try self.cp_manager.getUtf8String(signature_index)) |signature| {
            field.signature = try self.allocator.dupe(u8, signature);
        }
    }

    /// 解析注解属性
    fn parseAnnotationsAttribute(self: *FieldParser, field: *FieldInfo, attr: *const bytecode.AttributeInfo, runtime_visible: bool) !void {
        _ = runtime_visible; // 暂时不使用

        if (attr.info.len < 2) {
            return error.InvalidAnnotationsAttribute;
        }

        const num_annotations = std.mem.readInt(u16, attr.info[0..2][0..2], .big);
        var pos: usize = 2;

        var i: u16 = 0;
        while (i < num_annotations and pos < attr.info.len) : (i += 1) {
            const annotation = try self.parseAnnotation(attr.info, &pos);
            try field.annotations.append(annotation);
        }
    }

    /// 解析单个注解
    fn parseAnnotation(self: *FieldParser, data: []const u8, pos: *usize) !bytecode.AnnotationInfo {
        if (pos.* + 4 > data.len) {
            return error.InvalidAnnotation;
        }

        const type_index = std.mem.readInt(u16, data[pos.* .. pos.* + 2][0..2], .big);
        pos.* += 2;

        const num_element_value_pairs = std.mem.readInt(u16, data[pos.* .. pos.* + 2][0..2], .big);
        pos.* += 2;

        var annotation = bytecode.AnnotationInfo{
            .type_index = type_index,
            .num_element_value_pairs = num_element_value_pairs,
            .element_value_pairs = try self.allocator.alloc(bytecode.ElementValuePair, num_element_value_pairs),
        };

        // 解析元素值对
        var i: u16 = 0;
        while (i < num_element_value_pairs) : (i += 1) {
            annotation.element_value_pairs[i] = try self.parseElementValuePair(data, pos);
        }

        return annotation;
    }

    /// 解析元素值对
    fn parseElementValuePair(self: *FieldParser, data: []const u8, pos: *usize) !bytecode.ElementValuePair {
        if (pos.* + 2 > data.len) {
            return error.InvalidElementValuePair;
        }

        const element_name_index = std.mem.readInt(u16, data[pos.* .. pos.* + 2][0..2], .big);
        pos.* += 2;

        const element_value = try self.parseElementValue(data, pos);

        return bytecode.ElementValuePair{
            .element_name_index = element_name_index,
            .value = element_value,
        };
    }

    /// 解析元素值
    fn parseElementValue(self: *FieldParser, data: []const u8, pos: *usize) !bytecode.ElementValue {
        if (pos.* >= data.len) {
            return error.InvalidElementValue;
        }

        const tag = data[pos.*];
        pos.* += 1;

        return switch (tag) {
            'B', 'C', 'D', 'F', 'I', 'J', 'S', 'Z', 's' => {
                if (pos.* + 2 > data.len) {
                    return error.InvalidElementValue;
                }
                const const_value_index = std.mem.readInt(u16, data[pos.* .. pos.* + 2][0..2], .big);
                pos.* += 2;

                return bytecode.ElementValue{
                    .tag = tag,
                    .value = bytecode.ElementValueUnion{ .const_value_index = const_value_index },
                };
            },
            'e' => {
                if (pos.* + 4 > data.len) {
                    return error.InvalidElementValue;
                }
                const type_name_index = std.mem.readInt(u16, data[pos.* .. pos.* + 2][0..2], .big);
                pos.* += 2;
                const const_name_index = std.mem.readInt(u16, data[pos.* .. pos.* + 2][0..2], .big);
                pos.* += 2;

                return bytecode.ElementValue{
                    .tag = tag,
                    .value = bytecode.ElementValueUnion{
                        .enum_const_value = bytecode.EnumConstValue{
                            .type_name_index = type_name_index,
                            .const_name_index = const_name_index,
                        },
                    },
                };
            },
            'c' => {
                if (pos.* + 2 > data.len) {
                    return error.InvalidElementValue;
                }
                const class_info_index = std.mem.readInt(u16, data[pos.* .. pos.* + 2][0..2], .big);
                pos.* += 2;

                return bytecode.ElementValue{
                    .tag = tag,
                    .value = bytecode.ElementValueUnion{ .class_info_index = class_info_index },
                };
            },
            '@' => {
                const annotation_value = try self.parseAnnotation(data, pos);

                return bytecode.ElementValue{
                    .tag = tag,
                    .value = bytecode.ElementValueUnion{ .annotation_value = annotation_value },
                };
            },
            '[' => {
                if (pos.* + 2 > data.len) {
                    return error.InvalidElementValue;
                }
                const num_values = std.mem.readInt(u16, data[pos.* .. pos.* + 2][0..2], .big);
                pos.* += 2;

                const values = try self.allocator.alloc(bytecode.ElementValue, num_values);
                var i: u16 = 0;
                while (i < num_values) : (i += 1) {
                    values[i] = try self.parseElementValue(data, pos);
                }

                return bytecode.ElementValue{
                    .tag = tag,
                    .value = bytecode.ElementValueUnion{
                        .array_value = bytecode.ArrayValue{
                            .num_values = num_values,
                            .values = values,
                        },
                    },
                };
            },
            else => return error.InvalidElementValueTag,
        };
    }

    /// 获取常量值
    fn getConstantValue(self: *FieldParser, constant_index: u16, field_type: JavaType) !JavaValue {
        const constant = self.constant_pool[constant_index - 1];

        return switch (field_type) {
            .int, .short, .char, .byte, .boolean => {
                if (constant == .integer) {
                    return JavaValue{ .int = constant.integer.value };
                }
                return error.TypeMismatch;
            },
            .long => {
                if (constant == .long) {
                    return JavaValue{ .long = constant.long.value };
                }
                return error.TypeMismatch;
            },
            .float => {
                if (constant == .float) {
                    return JavaValue{ .float = constant.float.value };
                }
                return error.TypeMismatch;
            },
            .double => {
                if (constant == .double) {
                    return JavaValue{ .double = constant.double.value };
                }
                return error.TypeMismatch;
            },
            .object => {
                if (constant == .string) {
                    const string_value = try self.cp_manager.getUtf8String(constant.string.string_index);
                    return JavaValue{ .reference = @ptrCast(string_value) };
                }
                return error.TypeMismatch;
            },
            else => return error.UnsupportedConstantType,
        };
    }

    /// 验证字段描述符
    fn validateFieldDescriptor(self: *FieldParser, descriptor: []const u8) !void {
        var pos: usize = 0;
        _ = try self.parseFieldDescriptorAt(descriptor, &pos);

        if (pos != descriptor.len) {
            return error.InvalidFieldDescriptor;
        }
    }

    /// 获取字段的 JVM 类型签名
    fn getJvmTypeSignature(self: *FieldParser, descriptor: FieldDescriptor, allocator: Allocator) ![]u8 {
        return switch (descriptor.field_type) {
            .byte => try allocator.dupe(u8, "B"),
            .char => try allocator.dupe(u8, "C"),
            .double => try allocator.dupe(u8, "D"),
            .float => try allocator.dupe(u8, "F"),
            .int => try allocator.dupe(u8, "I"),
            .long => try allocator.dupe(u8, "J"),
            .short => try allocator.dupe(u8, "S"),
            .boolean => try allocator.dupe(u8, "Z"),
            .object => {
                if (descriptor.class_name) |class_name| {
                    return std.fmt.allocPrint(allocator, "L{s};", .{class_name});
                }
                return error.MissingClassName;
            },
            .array => {
                const signature = try allocator.alloc(u8, descriptor.array_dimensions);
                @memset(signature, '[');

                if (descriptor.component_type) |component_type| {
                    const component_sig = try self.getJvmTypeSignature(
                        FieldDescriptor.primitive(component_type),
                        allocator,
                    );
                    defer allocator.free(component_sig);

                    const full_signature = try std.fmt.allocPrint(
                        allocator,
                        "{s}{s}",
                        .{ signature, component_sig },
                    );
                    allocator.free(signature);
                    return full_signature;
                }
                return signature;
            },
            else => return error.UnsupportedFieldType,
        };
    }
};

/// 创建字段解析器
fn createFieldParser(allocator: Allocator, cp_entries: []const bytecode.ConstantPoolEntry, cp_manager: *constant_pool.ConstantPoolManager) FieldParser {
    return FieldParser.init(allocator, cp_entries, cp_manager);
}

/// 解析字段描述符字符串
fn parseFieldDescriptorString(descriptor: []const u8, allocator: Allocator) !FieldDescriptor {
    var dummy_cp = [_]bytecode.ConstantPoolEntry{};
    var dummy_manager = try constant_pool.ConstantPoolManager.init(&dummy_cp, allocator);
    defer dummy_manager.deinit();

    var parser = FieldParser.init(allocator, &dummy_cp, &dummy_manager);
    return parser.parseFieldDescriptor(descriptor);
}

// 导出公共接口
const exports = struct {
    const JavaType = @This().JavaType;
    const FieldDescriptor = @This().FieldDescriptor;
    const FieldInfo = @This().FieldInfo;
    const FieldParser = @This().FieldParser;
    const createFieldParser = @This().createFieldParser;
    const parseFieldDescriptorString = @This().parseFieldDescriptorString;
};

test "字段描述符解析测试" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // 测试基本类型
    {
        const descriptor = try parseFieldDescriptorString("I", allocator);
        defer descriptor.deinit(allocator);

        try testing.expectEqual(JavaType.int, descriptor.field_type);
        try testing.expect(descriptor.isPrimitive());
        try testing.expectEqual(@as(u8, 1), descriptor.getSize());
    }

    // 测试对象类型
    {
        const descriptor = try parseFieldDescriptorString("Ljava/lang/String;", allocator);
        defer descriptor.deinit(allocator);

        try testing.expectEqual(JavaType.object, descriptor.field_type);
        try testing.expect(descriptor.isObject());
        try testing.expectEqualStrings("java/lang/String", descriptor.class_name.?);
    }

    // 测试数组类型
    {
        const descriptor = try parseFieldDescriptorString("[I", allocator);
        defer descriptor.deinit(allocator);

        try testing.expectEqual(JavaType.array, descriptor.field_type);
        try testing.expect(descriptor.isArray());
        try testing.expectEqual(@as(u8, 1), descriptor.array_dimensions);
        try testing.expectEqual(JavaType.int, descriptor.component_type.?);
    }

    // 测试多维数组
    {
        const descriptor = try parseFieldDescriptorString("[[Ljava/lang/Object;", allocator);
        defer descriptor.deinit(allocator);

        try testing.expectEqual(JavaType.array, descriptor.field_type);
        try testing.expectEqual(@as(u8, 2), descriptor.array_dimensions);
        try testing.expectEqual(JavaType.object, descriptor.component_type.?);
        try testing.expectEqualStrings("java/lang/Object", descriptor.class_name.?);
    }
}

test "Java 类型测试" {
    const testing = std.testing;

    // 测试类型大小
    try testing.expectEqual(@as(u8, 2), JavaType.long.getSize());
    try testing.expectEqual(@as(u8, 2), JavaType.double.getSize());
    try testing.expectEqual(@as(u8, 1), JavaType.int.getSize());

    // 测试基本类型检查
    try testing.expect(JavaType.int.isPrimitive());
    try testing.expect(!JavaType.object.isPrimitive());

    // 测试默认值
    const int_default = JavaType.int.getDefaultValue();
    try testing.expectEqual(@as(i32, 0), int_default.int);

    const ref_default = JavaType.object.getDefaultValue();
    try testing.expectEqual(@as(?*anyopaque, null), ref_default.reference);
}
