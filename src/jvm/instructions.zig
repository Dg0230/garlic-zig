//! JVM 字节码指令集定义
//! 包含所有 JVM 字节码指令的定义和相关操作

const std = @import("std");
const Allocator = std.mem.Allocator;

/// JVM 字节码指令枚举
pub const Opcode = enum(u8) {
    // 常量指令 (0x00-0x14)
    nop = 0x00,
    aconst_null = 0x01,
    iconst_m1 = 0x02,
    iconst_0 = 0x03,
    iconst_1 = 0x04,
    iconst_2 = 0x05,
    iconst_3 = 0x06,
    iconst_4 = 0x07,
    iconst_5 = 0x08,
    lconst_0 = 0x09,
    lconst_1 = 0x0a,
    fconst_0 = 0x0b,
    fconst_1 = 0x0c,
    fconst_2 = 0x0d,
    dconst_0 = 0x0e,
    dconst_1 = 0x0f,
    bipush = 0x10,
    sipush = 0x11,
    ldc = 0x12,
    ldc_w = 0x13,
    ldc2_w = 0x14,

    // 局部变量加载指令 (0x15-0x35)
    iload = 0x15,
    lload = 0x16,
    fload = 0x17,
    dload = 0x18,
    aload = 0x19,
    iload_0 = 0x1a,
    iload_1 = 0x1b,
    iload_2 = 0x1c,
    iload_3 = 0x1d,
    lload_0 = 0x1e,
    lload_1 = 0x1f,
    lload_2 = 0x20,
    lload_3 = 0x21,
    fload_0 = 0x22,
    fload_1 = 0x23,
    fload_2 = 0x24,
    fload_3 = 0x25,
    dload_0 = 0x26,
    dload_1 = 0x27,
    dload_2 = 0x28,
    dload_3 = 0x29,
    aload_0 = 0x2a,
    aload_1 = 0x2b,
    aload_2 = 0x2c,
    aload_3 = 0x2d,
    iaload = 0x2e,
    laload = 0x2f,
    faload = 0x30,
    daload = 0x31,
    aaload = 0x32,
    baload = 0x33,
    caload = 0x34,
    saload = 0x35,

    // 局部变量存储指令 (0x36-0x56)
    istore = 0x36,
    lstore = 0x37,
    fstore = 0x38,
    dstore = 0x39,
    astore = 0x3a,
    istore_0 = 0x3b,
    istore_1 = 0x3c,
    istore_2 = 0x3d,
    istore_3 = 0x3e,
    lstore_0 = 0x3f,
    lstore_1 = 0x40,
    lstore_2 = 0x41,
    lstore_3 = 0x42,
    fstore_0 = 0x43,
    fstore_1 = 0x44,
    fstore_2 = 0x45,
    fstore_3 = 0x46,
    dstore_0 = 0x47,
    dstore_1 = 0x48,
    dstore_2 = 0x49,
    dstore_3 = 0x4a,
    astore_0 = 0x4b,
    astore_1 = 0x4c,
    astore_2 = 0x4d,
    astore_3 = 0x4e,
    iastore = 0x4f,
    lastore = 0x50,
    fastore = 0x51,
    dastore = 0x52,
    aastore = 0x53,
    bastore = 0x54,
    castore = 0x55,
    sastore = 0x56,

    // 栈操作指令 (0x57-0x5f)
    pop = 0x57,
    pop2 = 0x58,
    dup = 0x59,
    dup_x1 = 0x5a,
    dup_x2 = 0x5b,
    dup2 = 0x5c,
    dup2_x1 = 0x5d,
    dup2_x2 = 0x5e,
    swap = 0x5f,

    // 算术指令 (0x60-0x83)
    iadd = 0x60,
    ladd = 0x61,
    fadd = 0x62,
    dadd = 0x63,
    isub = 0x64,
    lsub = 0x65,
    fsub = 0x66,
    dsub = 0x67,
    imul = 0x68,
    lmul = 0x69,
    fmul = 0x6a,
    dmul = 0x6b,
    idiv = 0x6c,
    ldiv = 0x6d,
    fdiv = 0x6e,
    ddiv = 0x6f,
    irem = 0x70,
    lrem = 0x71,
    frem = 0x72,
    drem = 0x73,
    ineg = 0x74,
    lneg = 0x75,
    fneg = 0x76,
    dneg = 0x77,
    ishl = 0x78,
    lshl = 0x79,
    ishr = 0x7a,
    lshr = 0x7b,
    iushr = 0x7c,
    lushr = 0x7d,
    iand = 0x7e,
    land = 0x7f,
    ior = 0x80,
    lor = 0x81,
    ixor = 0x82,
    lxor = 0x83,

    // 局部变量递增指令 (0x84)
    iinc = 0x84,

    // 类型转换指令 (0x85-0x93)
    i2l = 0x85,
    i2f = 0x86,
    i2d = 0x87,
    l2i = 0x88,
    l2f = 0x89,
    l2d = 0x8a,
    f2i = 0x8b,
    f2l = 0x8c,
    f2d = 0x8d,
    d2i = 0x8e,
    d2l = 0x8f,
    d2f = 0x90,
    i2b = 0x91,
    i2c = 0x92,
    i2s = 0x93,

    // 比较指令 (0x94-0xa6)
    lcmp = 0x94,
    fcmpl = 0x95,
    fcmpg = 0x96,
    dcmpl = 0x97,
    dcmpg = 0x98,
    ifeq = 0x99,
    ifne = 0x9a,
    iflt = 0x9b,
    ifge = 0x9c,
    ifgt = 0x9d,
    ifle = 0x9e,
    if_icmpeq = 0x9f,
    if_icmpne = 0xa0,
    if_icmplt = 0xa1,
    if_icmpge = 0xa2,
    if_icmpgt = 0xa3,
    if_icmple = 0xa4,
    if_acmpeq = 0xa5,
    if_acmpne = 0xa6,

    // 控制流指令 (0xa7-0xb1)
    goto = 0xa7,
    jsr = 0xa8,
    ret = 0xa9,
    tableswitch = 0xaa,
    lookupswitch = 0xab,
    ireturn = 0xac,
    lreturn = 0xad,
    freturn = 0xae,
    dreturn = 0xaf,
    areturn = 0xb0,
    @"return" = 0xb1,

    // 字段访问指令 (0xb2-0xb5)
    getstatic = 0xb2,
    putstatic = 0xb3,
    getfield = 0xb4,
    putfield = 0xb5,

    // 方法调用指令 (0xb6-0xba)
    invokevirtual = 0xb6,
    invokespecial = 0xb7,
    invokestatic = 0xb8,
    invokeinterface = 0xb9,
    invokedynamic = 0xba,

    // 对象创建指令 (0xbb-0xc3)
    new = 0xbb,
    newarray = 0xbc,
    anewarray = 0xbd,
    arraylength = 0xbe,
    athrow = 0xbf,
    checkcast = 0xc0,
    instanceof = 0xc1,
    monitorenter = 0xc2,
    monitorexit = 0xc3,

    // 扩展指令 (0xc4-0xc9)
    wide = 0xc4,
    multianewarray = 0xc5,
    ifnull = 0xc6,
    ifnonnull = 0xc7,
    goto_w = 0xc8,
    jsr_w = 0xc9,

    // 保留指令 (0xca-0xff)
    breakpoint = 0xca,
    impdep1 = 0xfe,
    impdep2 = 0xff,

    _,
};

/// 指令信息结构
pub const InstructionInfo = struct {
    opcode: Opcode,
    name: []const u8,
    operand_count: u8,
    stack_effect: i8, // 对栈的影响（正数表示压栈，负数表示出栈）
    category: InstructionCategory,
};

/// 指令分类
pub const InstructionCategory = enum {
    constant,
    load,
    store,
    stack,
    arithmetic,
    conversion,
    comparison,
    control,
    field,
    method,
    object,
    extended,
    reserved,
};

/// 获取指令信息
pub fn getInstructionInfo(opcode: Opcode) InstructionInfo {
    return switch (opcode) {
        .nop => .{ .opcode = .nop, .name = "nop", .operand_count = 0, .stack_effect = 0, .category = .constant },
        .aconst_null => .{ .opcode = .aconst_null, .name = "aconst_null", .operand_count = 0, .stack_effect = 1, .category = .constant },
        .iconst_m1 => .{ .opcode = .iconst_m1, .name = "iconst_m1", .operand_count = 0, .stack_effect = 1, .category = .constant },
        .iconst_0 => .{ .opcode = .iconst_0, .name = "iconst_0", .operand_count = 0, .stack_effect = 1, .category = .constant },
        .iconst_1 => .{ .opcode = .iconst_1, .name = "iconst_1", .operand_count = 0, .stack_effect = 1, .category = .constant },
        .iconst_2 => .{ .opcode = .iconst_2, .name = "iconst_2", .operand_count = 0, .stack_effect = 1, .category = .constant },
        .iconst_3 => .{ .opcode = .iconst_3, .name = "iconst_3", .operand_count = 0, .stack_effect = 1, .category = .constant },
        .iconst_4 => .{ .opcode = .iconst_4, .name = "iconst_4", .operand_count = 0, .stack_effect = 1, .category = .constant },
        .iconst_5 => .{ .opcode = .iconst_5, .name = "iconst_5", .operand_count = 0, .stack_effect = 1, .category = .constant },
        .lconst_0 => .{ .opcode = .lconst_0, .name = "lconst_0", .operand_count = 0, .stack_effect = 2, .category = .constant },
        .lconst_1 => .{ .opcode = .lconst_1, .name = "lconst_1", .operand_count = 0, .stack_effect = 2, .category = .constant },
        .fconst_0 => .{ .opcode = .fconst_0, .name = "fconst_0", .operand_count = 0, .stack_effect = 1, .category = .constant },
        .fconst_1 => .{ .opcode = .fconst_1, .name = "fconst_1", .operand_count = 0, .stack_effect = 1, .category = .constant },
        .fconst_2 => .{ .opcode = .fconst_2, .name = "fconst_2", .operand_count = 0, .stack_effect = 1, .category = .constant },
        .dconst_0 => .{ .opcode = .dconst_0, .name = "dconst_0", .operand_count = 0, .stack_effect = 2, .category = .constant },
        .dconst_1 => .{ .opcode = .dconst_1, .name = "dconst_1", .operand_count = 0, .stack_effect = 2, .category = .constant },
        .bipush => .{ .opcode = .bipush, .name = "bipush", .operand_count = 1, .stack_effect = 1, .category = .constant },
        .sipush => .{ .opcode = .sipush, .name = "sipush", .operand_count = 2, .stack_effect = 1, .category = .constant },
        .ldc => .{ .opcode = .ldc, .name = "ldc", .operand_count = 1, .stack_effect = 1, .category = .constant },
        .ldc_w => .{ .opcode = .ldc_w, .name = "ldc_w", .operand_count = 2, .stack_effect = 1, .category = .constant },
        .ldc2_w => .{ .opcode = .ldc2_w, .name = "ldc2_w", .operand_count = 2, .stack_effect = 2, .category = .constant },

        // 加载指令
        .iload => .{ .opcode = .iload, .name = "iload", .operand_count = 1, .stack_effect = 1, .category = .load },
        .lload => .{ .opcode = .lload, .name = "lload", .operand_count = 1, .stack_effect = 2, .category = .load },
        .fload => .{ .opcode = .fload, .name = "fload", .operand_count = 1, .stack_effect = 1, .category = .load },
        .dload => .{ .opcode = .dload, .name = "dload", .operand_count = 1, .stack_effect = 2, .category = .load },
        .aload => .{ .opcode = .aload, .name = "aload", .operand_count = 1, .stack_effect = 1, .category = .load },
        .iload_0 => .{ .opcode = .iload_0, .name = "iload_0", .operand_count = 0, .stack_effect = 1, .category = .load },
        .iload_1 => .{ .opcode = .iload_1, .name = "iload_1", .operand_count = 0, .stack_effect = 1, .category = .load },
        .iload_2 => .{ .opcode = .iload_2, .name = "iload_2", .operand_count = 0, .stack_effect = 1, .category = .load },
        .iload_3 => .{ .opcode = .iload_3, .name = "iload_3", .operand_count = 0, .stack_effect = 1, .category = .load },
        .aload_0 => .{ .opcode = .aload_0, .name = "aload_0", .operand_count = 0, .stack_effect = 1, .category = .load },
        .aload_1 => .{ .opcode = .aload_1, .name = "aload_1", .operand_count = 0, .stack_effect = 1, .category = .load },
        .aload_2 => .{ .opcode = .aload_2, .name = "aload_2", .operand_count = 0, .stack_effect = 1, .category = .load },
        .aload_3 => .{ .opcode = .aload_3, .name = "aload_3", .operand_count = 0, .stack_effect = 1, .category = .load },

        // 存储指令
        .istore => .{ .opcode = .istore, .name = "istore", .operand_count = 1, .stack_effect = -1, .category = .store },
        .lstore => .{ .opcode = .lstore, .name = "lstore", .operand_count = 1, .stack_effect = -2, .category = .store },
        .fstore => .{ .opcode = .fstore, .name = "fstore", .operand_count = 1, .stack_effect = -1, .category = .store },
        .dstore => .{ .opcode = .dstore, .name = "dstore", .operand_count = 1, .stack_effect = -2, .category = .store },
        .astore => .{ .opcode = .astore, .name = "astore", .operand_count = 1, .stack_effect = -1, .category = .store },
        .istore_0 => .{ .opcode = .istore_0, .name = "istore_0", .operand_count = 0, .stack_effect = -1, .category = .store },
        .istore_1 => .{ .opcode = .istore_1, .name = "istore_1", .operand_count = 0, .stack_effect = -1, .category = .store },
        .istore_2 => .{ .opcode = .istore_2, .name = "istore_2", .operand_count = 0, .stack_effect = -1, .category = .store },
        .istore_3 => .{ .opcode = .istore_3, .name = "istore_3", .operand_count = 0, .stack_effect = -1, .category = .store },
        .astore_0 => .{ .opcode = .astore_0, .name = "astore_0", .operand_count = 0, .stack_effect = -1, .category = .store },
        .astore_1 => .{ .opcode = .astore_1, .name = "astore_1", .operand_count = 0, .stack_effect = -1, .category = .store },
        .astore_2 => .{ .opcode = .astore_2, .name = "astore_2", .operand_count = 0, .stack_effect = -1, .category = .store },
        .astore_3 => .{ .opcode = .astore_3, .name = "astore_3", .operand_count = 0, .stack_effect = -1, .category = .store },

        // 算术指令
        .iadd => .{ .opcode = .iadd, .name = "iadd", .operand_count = 0, .stack_effect = -1, .category = .arithmetic },
        .ladd => .{ .opcode = .ladd, .name = "ladd", .operand_count = 0, .stack_effect = -2, .category = .arithmetic },
        .fadd => .{ .opcode = .fadd, .name = "fadd", .operand_count = 0, .stack_effect = -1, .category = .arithmetic },
        .dadd => .{ .opcode = .dadd, .name = "dadd", .operand_count = 0, .stack_effect = -2, .category = .arithmetic },
        .isub => .{ .opcode = .isub, .name = "isub", .operand_count = 0, .stack_effect = -1, .category = .arithmetic },
        .lsub => .{ .opcode = .lsub, .name = "lsub", .operand_count = 0, .stack_effect = -2, .category = .arithmetic },
        .fsub => .{ .opcode = .fsub, .name = "fsub", .operand_count = 0, .stack_effect = -1, .category = .arithmetic },
        .dsub => .{ .opcode = .dsub, .name = "dsub", .operand_count = 0, .stack_effect = -2, .category = .arithmetic },
        .imul => .{ .opcode = .imul, .name = "imul", .operand_count = 0, .stack_effect = -1, .category = .arithmetic },
        .lmul => .{ .opcode = .lmul, .name = "lmul", .operand_count = 0, .stack_effect = -2, .category = .arithmetic },
        .fmul => .{ .opcode = .fmul, .name = "fmul", .operand_count = 0, .stack_effect = -1, .category = .arithmetic },
        .dmul => .{ .opcode = .dmul, .name = "dmul", .operand_count = 0, .stack_effect = -2, .category = .arithmetic },
        .idiv => .{ .opcode = .idiv, .name = "idiv", .operand_count = 0, .stack_effect = -1, .category = .arithmetic },
        .ldiv => .{ .opcode = .ldiv, .name = "ldiv", .operand_count = 0, .stack_effect = -2, .category = .arithmetic },
        .fdiv => .{ .opcode = .fdiv, .name = "fdiv", .operand_count = 0, .stack_effect = -1, .category = .arithmetic },
        .ddiv => .{ .opcode = .ddiv, .name = "ddiv", .operand_count = 0, .stack_effect = -2, .category = .arithmetic },

        // 控制流指令
        .ifeq => .{ .opcode = .ifeq, .name = "ifeq", .operand_count = 2, .stack_effect = -1, .category = .control },
        .ifne => .{ .opcode = .ifne, .name = "ifne", .operand_count = 2, .stack_effect = -1, .category = .control },
        .iflt => .{ .opcode = .iflt, .name = "iflt", .operand_count = 2, .stack_effect = -1, .category = .control },
        .ifge => .{ .opcode = .ifge, .name = "ifge", .operand_count = 2, .stack_effect = -1, .category = .control },
        .ifgt => .{ .opcode = .ifgt, .name = "ifgt", .operand_count = 2, .stack_effect = -1, .category = .control },
        .ifle => .{ .opcode = .ifle, .name = "ifle", .operand_count = 2, .stack_effect = -1, .category = .control },
        .goto => .{ .opcode = .goto, .name = "goto", .operand_count = 2, .stack_effect = 0, .category = .control },
        .@"return" => .{ .opcode = .@"return", .name = "return", .operand_count = 0, .stack_effect = 0, .category = .control },
        .ireturn => .{ .opcode = .ireturn, .name = "ireturn", .operand_count = 0, .stack_effect = -1, .category = .control },
        .lreturn => .{ .opcode = .lreturn, .name = "lreturn", .operand_count = 0, .stack_effect = -2, .category = .control },
        .freturn => .{ .opcode = .freturn, .name = "freturn", .operand_count = 0, .stack_effect = -1, .category = .control },
        .dreturn => .{ .opcode = .dreturn, .name = "dreturn", .operand_count = 0, .stack_effect = -2, .category = .control },
        .areturn => .{ .opcode = .areturn, .name = "areturn", .operand_count = 0, .stack_effect = -1, .category = .control },

        // 方法调用指令
        .invokevirtual => .{ .opcode = .invokevirtual, .name = "invokevirtual", .operand_count = 2, .stack_effect = 0, .category = .method }, // 栈效果取决于方法签名
        .invokespecial => .{ .opcode = .invokespecial, .name = "invokespecial", .operand_count = 2, .stack_effect = 0, .category = .method },
        .invokestatic => .{ .opcode = .invokestatic, .name = "invokestatic", .operand_count = 2, .stack_effect = 0, .category = .method },
        .invokeinterface => .{ .opcode = .invokeinterface, .name = "invokeinterface", .operand_count = 4, .stack_effect = 0, .category = .method },
        .invokedynamic => .{ .opcode = .invokedynamic, .name = "invokedynamic", .operand_count = 4, .stack_effect = 0, .category = .method },

        // 字段访问指令
        .getstatic => .{ .opcode = .getstatic, .name = "getstatic", .operand_count = 2, .stack_effect = 1, .category = .field }, // 栈效果取决于字段类型
        .putstatic => .{ .opcode = .putstatic, .name = "putstatic", .operand_count = 2, .stack_effect = -1, .category = .field },
        .getfield => .{ .opcode = .getfield, .name = "getfield", .operand_count = 2, .stack_effect = 0, .category = .field }, // -1 + 字段大小
        .putfield => .{ .opcode = .putfield, .name = "putfield", .operand_count = 2, .stack_effect = -2, .category = .field }, // -1 - 字段大小

        // 对象创建指令
        .new => .{ .opcode = .new, .name = "new", .operand_count = 2, .stack_effect = 1, .category = .object },
        .newarray => .{ .opcode = .newarray, .name = "newarray", .operand_count = 1, .stack_effect = 0, .category = .object },
        .anewarray => .{ .opcode = .anewarray, .name = "anewarray", .operand_count = 2, .stack_effect = 0, .category = .object },
        .arraylength => .{ .opcode = .arraylength, .name = "arraylength", .operand_count = 0, .stack_effect = 0, .category = .object },
        .checkcast => .{ .opcode = .checkcast, .name = "checkcast", .operand_count = 2, .stack_effect = 0, .category = .object },
        .instanceof => .{ .opcode = .instanceof, .name = "instanceof", .operand_count = 2, .stack_effect = 0, .category = .object },

        // 调试指令
        .breakpoint => .{ .opcode = .breakpoint, .name = "breakpoint", .operand_count = 0, .stack_effect = 0, .category = .reserved },

        else => .{ .opcode = opcode, .name = "unknown", .operand_count = 0, .stack_effect = 0, .category = .reserved },
    };
}

/// 检查指令是否为分支指令
pub fn isBranchInstruction(opcode: Opcode) bool {
    return switch (opcode) {
        .ifeq, .ifne, .iflt, .ifge, .ifgt, .ifle, .if_icmpeq, .if_icmpne, .if_icmplt, .if_icmpge, .if_icmpgt, .if_icmple, .if_acmpeq, .if_acmpne, .ifnull, .ifnonnull, .goto, .goto_w, .jsr, .jsr_w, .tableswitch, .lookupswitch => true,
        else => false,
    };
}

/// 检查指令是否为返回指令
pub fn isReturnInstruction(opcode: Opcode) bool {
    return switch (opcode) {
        .ireturn, .lreturn, .freturn, .dreturn, .areturn, .@"return" => true,
        else => false,
    };
}

/// 检查指令是否为方法调用指令
pub fn isInvokeInstruction(opcode: Opcode) bool {
    return switch (opcode) {
        .invokevirtual, .invokespecial, .invokestatic, .invokeinterface, .invokedynamic => true,
        else => false,
    };
}

/// 检查指令是否会抛出异常
pub fn canThrowException(opcode: Opcode) bool {
    return switch (opcode) {
        .idiv,
        .ldiv,
        .irem,
        .lrem, // 除零异常
        .iaload,
        .laload,
        .faload,
        .daload,
        .aaload,
        .baload,
        .caload,
        .saload, // 数组访问异常
        .iastore,
        .lastore,
        .fastore,
        .dastore,
        .aastore,
        .bastore,
        .castore,
        .sastore,
        .arraylength, // 空指针异常
        .athrow, // 显式抛出异常
        .checkcast, // 类型转换异常
        .new,
        .newarray,
        .anewarray,
        .multianewarray, // 内存不足异常
        .getfield,
        .putfield, // 空指针异常
        .invokevirtual,
        .invokespecial,
        .invokestatic,
        .invokeinterface,
        .invokedynamic, // 方法调用异常
        .monitorenter,
        .monitorexit,
        => true, // 同步异常
        else => false,
    };
}

test "instruction info" {
    const testing = std.testing;

    // 测试常量指令
    const nop_info = getInstructionInfo(.nop);
    try testing.expect(nop_info.opcode == .nop);
    try testing.expect(std.mem.eql(u8, nop_info.name, "nop"));
    try testing.expect(nop_info.operand_count == 0);
    try testing.expect(nop_info.stack_effect == 0);
    try testing.expect(nop_info.category == .constant);

    // 测试加载指令
    const iload_info = getInstructionInfo(.iload);
    try testing.expect(iload_info.category == .load);
    try testing.expect(iload_info.stack_effect == 1);

    // 测试分支指令检查
    try testing.expect(isBranchInstruction(.ifeq));
    try testing.expect(isBranchInstruction(.goto));
    try testing.expect(!isBranchInstruction(.nop));

    // 测试返回指令检查
    try testing.expect(isReturnInstruction(.ireturn));
    try testing.expect(isReturnInstruction(.@"return"));
    try testing.expect(!isReturnInstruction(.nop));

    // 测试方法调用指令检查
    try testing.expect(isInvokeInstruction(.invokevirtual));
    try testing.expect(isInvokeInstruction(.invokestatic));
    try testing.expect(!isInvokeInstruction(.nop));

    // 测试异常抛出检查
    try testing.expect(canThrowException(.idiv));
    try testing.expect(canThrowException(.athrow));
    try testing.expect(!canThrowException(.nop));
}
