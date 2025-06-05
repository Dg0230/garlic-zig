//! Java 方法解析器
//! 负责解析方法签名、字节码指令、局部变量表和异常表等方法相关信息

const std = @import("std");
const types = @import("../common/types.zig");
const bytecode = @import("bytecode.zig");
const constant_pool = @import("constant_pool.zig");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;

/// 方法信息（重新导出）
const MethodInfo = bytecode.MethodInfo;
const AttributeInfo = bytecode.AttributeInfo;
const ConstantPoolManager = constant_pool.ConstantPoolManager;

/// Java 基本类型
const JavaType = enum {
    byte,
    char,
    double,
    float,
    int,
    long,
    reference, // 对象引用
    short,
    boolean,
    void,
    array,

    /// 从描述符字符获取类型
    fn fromDescriptor(char: u8) ?JavaType {
        return switch (char) {
            'B' => .byte,
            'C' => .char,
            'D' => .double,
            'F' => .float,
            'I' => .int,
            'J' => .long,
            'L' => .reference,
            'S' => .short,
            'Z' => .boolean,
            'V' => .void,
            '[' => .array,
            else => null,
        };
    }

    /// 获取类型的大小（在操作数栈中占用的槽位数）
    fn getSize(self: JavaType) u8 {
        return switch (self) {
            .long, .double => 2,
            else => 1,
        };
    }
};

/// 方法参数信息
const ParameterInfo = struct {
    type: JavaType,
    class_name: ?[]const u8, // 对于引用类型
    array_dimensions: u8, // 数组维度
};

/// 方法签名信息
const MethodSignature = struct {
    parameters: ArrayList(ParameterInfo),
    return_type: ParameterInfo,
    allocator: Allocator,

    /// 释放资源
    fn deinit(self: *MethodSignature) void {
        self.parameters.deinit();
    }
};

/// 局部变量表条目
const LocalVariableEntry = struct {
    start_pc: u16,
    length: u16,
    name_index: u16,
    descriptor_index: u16,
    index: u16,
};

/// 异常表条目
const ExceptionTableEntry = struct {
    start_pc: u16,
    end_pc: u16,
    handler_pc: u16,
    catch_type: u16, // 0 表示 finally
};

/// 字节码指令信息
const BytecodeInstruction = struct {
    opcode: u8,
    pc: u16, // 程序计数器
    operands: []u8,

    /// 获取指令名称
    fn getOpcodeName(opcode: u8) []const u8 {
        return switch (opcode) {
            0x00 => "nop",
            0x01 => "aconst_null",
            0x02 => "iconst_m1",
            0x03 => "iconst_0",
            0x04 => "iconst_1",
            0x05 => "iconst_2",
            0x06 => "iconst_3",
            0x07 => "iconst_4",
            0x08 => "iconst_5",
            0x09 => "lconst_0",
            0x0A => "lconst_1",
            0x0B => "fconst_0",
            0x0C => "fconst_1",
            0x0D => "fconst_2",
            0x0E => "dconst_0",
            0x0F => "dconst_1",
            0x10 => "bipush",
            0x11 => "sipush",
            0x12 => "ldc",
            0x13 => "ldc_w",
            0x14 => "ldc2_w",
            0x15 => "iload",
            0x16 => "lload",
            0x17 => "fload",
            0x18 => "dload",
            0x19 => "aload",
            0x1A => "iload_0",
            0x1B => "iload_1",
            0x1C => "iload_2",
            0x1D => "iload_3",
            0x36 => "istore",
            0x37 => "lstore",
            0x38 => "fstore",
            0x39 => "dstore",
            0x3A => "astore",
            0x3B => "istore_0",
            0x3C => "istore_1",
            0x3D => "istore_2",
            0x3E => "istore_3",
            0x57 => "pop",
            0x58 => "pop2",
            0x59 => "dup",
            0x5A => "dup_x1",
            0x5B => "dup_x2",
            0x5C => "dup2",
            0x5D => "dup2_x1",
            0x5E => "dup2_x2",
            0x5F => "swap",
            0x60 => "iadd",
            0x61 => "ladd",
            0x62 => "fadd",
            0x63 => "dadd",
            0x64 => "isub",
            0x65 => "lsub",
            0x66 => "fsub",
            0x67 => "dsub",
            0x68 => "imul",
            0x69 => "lmul",
            0x6A => "fmul",
            0x6B => "dmul",
            0x6C => "idiv",
            0x6D => "ldiv",
            0x6E => "fdiv",
            0x6F => "ddiv",
            0x70 => "irem",
            0x71 => "lrem",
            0x72 => "frem",
            0x73 => "drem",
            0x74 => "ineg",
            0x75 => "lneg",
            0x76 => "fneg",
            0x77 => "dneg",
            0x78 => "ishl",
            0x79 => "lshl",
            0x7A => "ishr",
            0x7B => "lshr",
            0x7C => "iushr",
            0x7D => "lushr",
            0x7E => "iand",
            0x7F => "land",
            0x80 => "ior",
            0x81 => "lor",
            0x82 => "ixor",
            0x83 => "lxor",
            0x84 => "iinc",
            0x85 => "i2l",
            0x86 => "i2f",
            0x87 => "i2d",
            0x88 => "l2i",
            0x89 => "l2f",
            0x8A => "l2d",
            0x8B => "f2i",
            0x8C => "f2l",
            0x8D => "f2d",
            0x8E => "d2i",
            0x8F => "d2l",
            0x90 => "d2f",
            0x91 => "i2b",
            0x92 => "i2c",
            0x93 => "i2s",
            0x94 => "lcmp",
            0x95 => "fcmpl",
            0x96 => "fcmpg",
            0x97 => "dcmpl",
            0x98 => "dcmpg",
            0x99 => "ifeq",
            0x9A => "ifne",
            0x9B => "iflt",
            0x9C => "ifge",
            0x9D => "ifgt",
            0x9E => "ifle",
            0x9F => "if_icmpeq",
            0xA0 => "if_icmpne",
            0xA1 => "if_icmplt",
            0xA2 => "if_icmpge",
            0xA3 => "if_icmpgt",
            0xA4 => "if_icmple",
            0xA5 => "if_acmpeq",
            0xA6 => "if_acmpne",
            0xA7 => "goto",
            0xA8 => "jsr",
            0xA9 => "ret",
            0xAA => "tableswitch",
            0xAB => "lookupswitch",
            0xAC => "ireturn",
            0xAD => "lreturn",
            0xAE => "freturn",
            0xAF => "dreturn",
            0xB0 => "areturn",
            0xB1 => "return",
            0xB2 => "getstatic",
            0xB3 => "putstatic",
            0xB4 => "getfield",
            0xB5 => "putfield",
            0xB6 => "invokevirtual",
            0xB7 => "invokespecial",
            0xB8 => "invokestatic",
            0xB9 => "invokeinterface",
            0xBA => "invokedynamic",
            0xBB => "new",
            0xBC => "newarray",
            0xBD => "anewarray",
            0xBE => "arraylength",
            0xBF => "athrow",
            0xC0 => "checkcast",
            0xC1 => "instanceof",
            0xC2 => "monitorenter",
            0xC3 => "monitorexit",
            0xC4 => "wide",
            0xC5 => "multianewarray",
            0xC6 => "ifnull",
            0xC7 => "ifnonnull",
            0xC8 => "goto_w",
            0xC9 => "jsr_w",
            else => "unknown",
        };
    }

    /// 获取指令操作数长度
    fn getOperandLength(opcode: u8) u8 {
        return switch (opcode) {
            0x00...0x0F => 0, // 常量指令
            0x10 => 1, // bipush
            0x11 => 2, // sipush
            0x12 => 1, // ldc
            0x13, 0x14 => 2, // ldc_w, ldc2_w
            0x15...0x19 => 1, // 加载指令
            0x1A...0x35 => 0, // 快速加载指令
            0x36...0x3A => 1, // 存储指令
            0x3B...0x56 => 0, // 快速存储指令
            0x57...0x83 => 0, // 栈操作和算术指令
            0x84 => 2, // iinc
            0x85...0x98 => 0, // 类型转换和比较指令
            0x99...0xA6 => 2, // 条件跳转指令
            0xA7, 0xA8 => 2, // goto, jsr
            0xA9 => 1, // ret
            0xAA => 0, // tableswitch (变长)
            0xAB => 0, // lookupswitch (变长)
            0xAC...0xB1 => 0, // 返回指令
            0xB2...0xB5 => 2, // 字段访问指令
            0xB6...0xB8 => 2, // 方法调用指令
            0xB9 => 4, // invokeinterface
            0xBA => 4, // invokedynamic
            0xBB => 2, // new
            0xBC => 1, // newarray
            0xBD => 2, // anewarray
            0xBE, 0xBF => 0, // arraylength, athrow
            0xC0, 0xC1 => 2, // checkcast, instanceof
            0xC2, 0xC3 => 0, // monitor指令
            0xC4 => 0, // wide (变长)
            0xC5 => 3, // multianewarray
            0xC6, 0xC7 => 2, // ifnull, ifnonnull
            0xC8, 0xC9 => 4, // goto_w, jsr_w
            else => 0,
        };
    }
};

/// 代码属性信息
const CodeAttribute = struct {
    max_stack: u16,
    max_locals: u16,
    code: []BytecodeInstruction,
    exception_table: []ExceptionTableEntry,
    attributes: []AttributeInfo,
    allocator: Allocator,

    /// 释放资源
    fn deinit(self: *CodeAttribute) void {
        for (self.code) |instruction| {
            self.allocator.free(instruction.operands);
        }
        self.allocator.free(self.code);
        self.allocator.free(self.exception_table);

        for (self.attributes) |attr| {
            self.allocator.free(attr.info);
        }
        self.allocator.free(self.attributes);
    }
};

/// 方法解析器
const MethodParser = struct {
    constant_pool: *ConstantPoolManager,
    allocator: Allocator,

    /// 创建方法解析器
    fn init(cp_manager: *ConstantPoolManager, allocator: Allocator) MethodParser {
        return MethodParser{
            .constant_pool = cp_manager,
            .allocator = allocator,
        };
    }

    /// 解析方法描述符
    fn parseMethodDescriptor(self: *MethodParser, descriptor: []const u8) !MethodSignature {
        var parameters = ArrayList(ParameterInfo).init(self.allocator);

        if (descriptor.len < 3 or descriptor[0] != '(') {
            return error.InvalidMethodDescriptor;
        }

        var i: usize = 1;

        // 解析参数
        while (i < descriptor.len and descriptor[i] != ')') {
            const param = try self.parseTypeDescriptor(descriptor, &i);
            try parameters.append(param);
        }

        if (i >= descriptor.len or descriptor[i] != ')') {
            return error.InvalidMethodDescriptor;
        }

        i += 1; // 跳过 ')'

        // 解析返回类型
        const return_type = try self.parseTypeDescriptor(descriptor, &i);

        return MethodSignature{
            .parameters = parameters,
            .return_type = return_type,
            .allocator = self.allocator,
        };
    }

    /// 解析类型描述符
    fn parseTypeDescriptor(_: *MethodParser, descriptor: []const u8, index: *usize) !ParameterInfo {
        if (index.* >= descriptor.len) {
            return error.InvalidTypeDescriptor;
        }

        var array_dimensions: u8 = 0;

        // 处理数组维度
        while (index.* < descriptor.len and descriptor[index.*] == '[') {
            array_dimensions += 1;
            index.* += 1;
        }

        if (index.* >= descriptor.len) {
            return error.InvalidTypeDescriptor;
        }

        const type_char = descriptor[index.*];
        index.* += 1;

        if (JavaType.fromDescriptor(type_char)) |java_type| {
            var class_name: ?[]const u8 = null;

            // 处理引用类型
            if (java_type == .reference) {
                const start = index.*;
                while (index.* < descriptor.len and descriptor[index.*] != ';') {
                    index.* += 1;
                }

                if (index.* >= descriptor.len or descriptor[index.*] != ';') {
                    return error.InvalidTypeDescriptor;
                }

                class_name = descriptor[start..index.*];
                index.* += 1; // 跳过 ';'
            }

            return ParameterInfo{
                .type = if (array_dimensions > 0) .array else java_type,
                .class_name = class_name,
                .array_dimensions = array_dimensions,
            };
        } else {
            return error.InvalidTypeDescriptor;
        }
    }

    /// 解析代码属性
    fn parseCodeAttribute(self: *MethodParser, attribute_data: []const u8) !CodeAttribute {
        if (attribute_data.len < 8) {
            return error.InvalidCodeAttribute;
        }

        var pos: usize = 0;

        // 读取栈和局部变量信息
        const max_stack = std.mem.readInt(u16, attribute_data[pos .. pos + 2][0..2], .big);
        pos += 2;
        const max_locals = std.mem.readInt(u16, attribute_data[pos .. pos + 2][0..2], .big);
        pos += 2;

        // 读取代码长度
        const code_length = std.mem.readInt(u32, attribute_data[pos .. pos + 4][0..4], .big);
        pos += 4;

        if (pos + code_length > attribute_data.len) {
            return error.InvalidCodeAttribute;
        }

        // 解析字节码指令
        const code = try self.parseInstructions(attribute_data[pos .. pos + code_length]);
        pos += code_length;

        // 读取异常表
        if (pos + 2 > attribute_data.len) {
            return error.InvalidCodeAttribute;
        }

        const exception_table_length = std.mem.readInt(u16, attribute_data[pos .. pos + 2][0..2], .big);
        pos += 2;

        const exception_table = try self.allocator.alloc(ExceptionTableEntry, exception_table_length);
        for (exception_table) |*entry| {
            if (pos + 8 > attribute_data.len) {
                return error.InvalidCodeAttribute;
            }

            entry.start_pc = std.mem.readInt(u16, attribute_data[pos .. pos + 2][0..2], .big);
            pos += 2;
            entry.end_pc = std.mem.readInt(u16, attribute_data[pos .. pos + 2][0..2], .big);
            pos += 2;
            entry.handler_pc = std.mem.readInt(u16, attribute_data[pos .. pos + 2][0..2], .big);
            pos += 2;
            entry.catch_type = std.mem.readInt(u16, attribute_data[pos .. pos + 2][0..2], .big);
            pos += 2;
        }

        // 读取属性
        if (pos + 2 > attribute_data.len) {
            return error.InvalidCodeAttribute;
        }

        const attributes_count = std.mem.readInt(u16, attribute_data[pos .. pos + 2][0..2], .big);
        pos += 2;

        const attributes = try self.allocator.alloc(AttributeInfo, attributes_count);
        for (attributes) |*attr| {
            if (pos + 6 > attribute_data.len) {
                return error.InvalidCodeAttribute;
            }

            attr.attribute_name_index = std.mem.readInt(u16, attribute_data[pos .. pos + 2][0..2], .big);
            pos += 2;
            attr.attribute_length = std.mem.readInt(u32, attribute_data[pos .. pos + 4][0..4], .big);
            pos += 4;

            if (pos + attr.attribute_length > attribute_data.len) {
                return error.InvalidCodeAttribute;
            }

            attr.info = try self.allocator.alloc(u8, attr.attribute_length);
            @memcpy(attr.info, attribute_data[pos .. pos + attr.attribute_length]);
            pos += attr.attribute_length;
        }

        return CodeAttribute{
            .max_stack = max_stack,
            .max_locals = max_locals,
            .code = code,
            .exception_table = exception_table,
            .attributes = attributes,
            .allocator = self.allocator,
        };
    }

    /// 解析字节码指令序列
    fn parseInstructions(self: *MethodParser, code_data: []const u8) ![]BytecodeInstruction {
        var instructions = ArrayList(BytecodeInstruction).init(self.allocator);
        var pc: u16 = 0;
        var pos: usize = 0;

        while (pos < code_data.len) {
            const opcode = code_data[pos];
            pos += 1;

            const operand_length = BytecodeInstruction.getOperandLength(opcode);
            var operands: []u8 = undefined;

            // 处理变长指令
            if (opcode == 0xAA) { // tableswitch
                operands = try self.parseTableswitchOperands(code_data, &pos, pc);
            } else if (opcode == 0xAB) { // lookupswitch
                operands = try self.parseLookupSwitchOperands(code_data, &pos, pc);
            } else if (opcode == 0xC4) { // wide
                operands = try self.parseWideOperands(code_data, &pos);
            } else {
                // 普通指令
                if (pos + operand_length > code_data.len) {
                    return error.InvalidBytecode;
                }

                operands = try self.allocator.alloc(u8, operand_length);
                if (operand_length > 0) {
                    @memcpy(operands, code_data[pos .. pos + operand_length]);
                    pos += operand_length;
                }
            }

            try instructions.append(BytecodeInstruction{
                .opcode = opcode,
                .pc = pc,
                .operands = operands,
            });

            pc = @intCast(pos);
        }

        return instructions.toOwnedSlice();
    }

    /// 解析 tableswitch 指令操作数
    fn parseTableswitchOperands(self: *MethodParser, code_data: []const u8, pos: *usize, pc: u16) ![]u8 {
        // 对齐到 4 字节边界
        const padding = (4 - ((pc + 1) % 4)) % 4;
        pos.* += padding;

        if (pos.* + 12 > code_data.len) {
            return error.InvalidBytecode;
        }

        // 读取默认跳转、低值和高值
        pos.* += 4; // default
        const low = std.mem.readInt(i32, code_data[pos.* .. pos.* + 4][0..4], .big);
        pos.* += 4;
        const high = std.mem.readInt(i32, code_data[pos.* .. pos.* + 4][0..4], .big);
        pos.* += 4;

        const jump_count = @as(usize, @intCast(high - low + 1));
        const total_size = padding + 12 + jump_count * 4;

        if (pos.* + jump_count * 4 > code_data.len) {
            return error.InvalidBytecode;
        }

        const operands = try self.allocator.alloc(u8, total_size);
        const start_pos = pos.* - padding - 12;
        @memcpy(operands, code_data[start_pos .. start_pos + total_size]);

        pos.* += jump_count * 4;
        return operands;
    }

    /// 解析 lookupswitch 指令操作数
    fn parseLookupSwitchOperands(self: *MethodParser, code_data: []const u8, pos: *usize, pc: u16) ![]u8 {
        // 对齐到 4 字节边界
        const padding = (4 - ((pc + 1) % 4)) % 4;
        pos.* += padding;

        if (pos.* + 8 > code_data.len) {
            return error.InvalidBytecode;
        }

        // 读取默认跳转和匹配对数量
        pos.* += 4; // default
        const npairs = std.mem.readInt(i32, code_data[pos.* .. pos.* + 4][0..4], .big);
        pos.* += 4;

        const pairs_size = @as(usize, @intCast(npairs)) * 8;
        const total_size = padding + 8 + pairs_size;

        if (pos.* + pairs_size > code_data.len) {
            return error.InvalidBytecode;
        }

        const operands = try self.allocator.alloc(u8, total_size);
        const start_pos = pos.* - padding - 8;
        @memcpy(operands, code_data[start_pos .. start_pos + total_size]);

        pos.* += pairs_size;
        return operands;
    }

    /// 解析 wide 指令操作数
    fn parseWideOperands(self: *MethodParser, code_data: []const u8, pos: *usize) ![]u8 {
        if (pos.* >= code_data.len) {
            return error.InvalidBytecode;
        }

        const modified_opcode = code_data[pos.*];
        pos.* += 1;

        const operand_length: usize = if (modified_opcode == 0x84) 4 else 2; // iinc 需要 4 字节，其他需要 2 字节

        if (pos.* + operand_length > code_data.len) {
            return error.InvalidBytecode;
        }

        const operands = try self.allocator.alloc(u8, 1 + operand_length);
        operands[0] = modified_opcode;
        @memcpy(operands[1..], code_data[pos.* .. pos.* + operand_length]);

        pos.* += operand_length;
        return operands;
    }

    /// 获取方法的代码属性
    fn getCodeAttribute(self: *MethodParser, method: *const MethodInfo) !?CodeAttribute {
        for (method.attributes) |attr| {
            const attr_name = try self.constant_pool.getUtf8String(attr.attribute_name_index);
            if (std.mem.eql(u8, attr_name, "Code")) {
                return try self.parseCodeAttribute(attr.info);
            }
        }
        return null;
    }

    /// 获取方法签名
    fn getMethodSignature(self: *MethodParser, method: *const MethodInfo) !MethodSignature {
        const descriptor = try self.constant_pool.getUtf8String(method.descriptor_index);
        return self.parseMethodDescriptor(descriptor);
    }

    /// 获取方法名称
    fn getMethodName(self: *MethodParser, method: *const MethodInfo) ![]const u8 {
        return self.constant_pool.getUtf8String(method.name_index);
    }

    /// 检查方法是否为构造函数
    fn isConstructor(self: *MethodParser, method: *const MethodInfo) !bool {
        const name = try self.getMethodName(method);
        return std.mem.eql(u8, name, "<init>");
    }

    /// 检查方法是否为静态初始化块
    fn isStaticInitializer(self: *MethodParser, method: *const MethodInfo) !bool {
        const name = try self.getMethodName(method);
        return std.mem.eql(u8, name, "<clinit>");
    }
};

// 导出公共接口
const exports = struct {
    const MethodParser = @This().MethodParser;
    const MethodSignature = @This().MethodSignature;
    const ParameterInfo = @This().ParameterInfo;
    const JavaType = @This().JavaType;
    const CodeAttribute = @This().CodeAttribute;
    const BytecodeInstruction = @This().BytecodeInstruction;
    const ExceptionTableEntry = @This().ExceptionTableEntry;
    const LocalVariableEntry = @This().LocalVariableEntry;
};

test "方法描述符解析测试" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // 创建一个简单的常量池管理器用于测试
    var entries = [_]bytecode.ConstantPoolEntry{};
    var cp_manager = try constant_pool.ConstantPoolManager.init(&entries, allocator);
    defer cp_manager.deinit();

    var parser = MethodParser.init(&cp_manager, allocator);

    // 测试简单方法描述符
    var signature = try parser.parseMethodDescriptor("()V");
    defer signature.deinit();

    try testing.expectEqual(@as(usize, 0), signature.parameters.items.len);
    try testing.expectEqual(JavaType.void, signature.return_type.type);

    // 测试带参数的方法描述符
    var signature2 = try parser.parseMethodDescriptor("(ILjava/lang/String;)Z");
    defer signature2.deinit();

    try testing.expectEqual(@as(usize, 2), signature2.parameters.items.len);
    try testing.expectEqual(JavaType.int, signature2.parameters.items[0].type);
    try testing.expectEqual(JavaType.reference, signature2.parameters.items[1].type);
    try testing.expectEqual(JavaType.boolean, signature2.return_type.type);
}

test "字节码指令解析测试" {
    const testing = std.testing;

    // 测试指令名称获取
    try testing.expectEqualStrings("nop", BytecodeInstruction.getOpcodeName(0x00));
    try testing.expectEqualStrings("iconst_0", BytecodeInstruction.getOpcodeName(0x03));
    try testing.expectEqualStrings("iload", BytecodeInstruction.getOpcodeName(0x15));
    try testing.expectEqualStrings("istore", BytecodeInstruction.getOpcodeName(0x36));
    try testing.expectEqualStrings("iadd", BytecodeInstruction.getOpcodeName(0x60));
    try testing.expectEqualStrings("ireturn", BytecodeInstruction.getOpcodeName(0xAC));

    // 测试操作数长度
    try testing.expectEqual(@as(u8, 0), BytecodeInstruction.getOperandLength(0x00)); // nop
    try testing.expectEqual(@as(u8, 1), BytecodeInstruction.getOperandLength(0x10)); // bipush
    try testing.expectEqual(@as(u8, 2), BytecodeInstruction.getOperandLength(0x11)); // sipush
    try testing.expectEqual(@as(u8, 2), BytecodeInstruction.getOperandLength(0xB6)); // invokevirtual
}
