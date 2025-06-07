const std = @import("std");
const print = std.debug.print;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const common = @import("common/types.zig");
const libs = @import("libs/mod.zig");
const parser = @import("parser/bytecode.zig");
const ZipReader = libs.zip.ZipReader;

/// 程序选项配置
const Options = struct {
    input_path: []const u8,
    output_path: ?[]const u8 = null,
    thread_count: u32 = 4,
    debug_mode: bool = false,
    verbose: bool = false,
    print_info_only: bool = false,
};

/// 创建输出目录
fn createOutputDir(path: []const u8) !void {
    std.fs.cwd().makeDir(path) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
}

/// 生成默认输出路径
fn generateDefaultOutputPath(allocator: Allocator, input_path: []const u8) ![]const u8 {
    const basename = std.fs.path.basename(input_path);
    const dirname = std.fs.path.dirname(input_path) orelse ".";

    // 移除扩展名并添加后缀
    const dot_index = std.mem.lastIndexOf(u8, basename, ".") orelse basename.len;
    const name_without_ext = basename[0..dot_index];

    return try std.fmt.allocPrint(allocator, "{s}/{s}_decompiled", .{ dirname, name_without_ext });
}

/// 文件类型枚举
const FileType = enum {
    java_class,
    jar_archive,
    dex_file,
    unknown,
};

/// 检测文件类型
fn detectFileType(path: []const u8, allocator: Allocator) !FileType {
    _ = allocator;
    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        print("[garlic] 无法打开文件: {s}\n", .{path});
        return err;
    };
    defer file.close();

    var magic: [4]u8 = undefined;
    const bytes_read = try file.readAll(&magic);

    if (bytes_read < 4) {
        print("[garlic] 文件 {s} 小于 4 字节\n", .{path});
        return FileType.unknown;
    }

    // Java Class 文件魔数: 0xCAFEBABE
    if (std.mem.eql(u8, &magic, &[_]u8{ 0xCA, 0xFE, 0xBA, 0xBE })) {
        return FileType.java_class;
    }

    // JAR/ZIP 文件魔数: 0x504B0304
    if (std.mem.eql(u8, &magic, &[_]u8{ 0x50, 0x4B, 0x03, 0x04 })) {
        return FileType.jar_archive;
    }

    // DEX 文件魔数: "dex\n"
    if (std.mem.eql(u8, &magic, &[_]u8{ 0x64, 0x65, 0x78, 0x0A })) {
        return FileType.dex_file;
    }

    return FileType.unknown;
}

/// 解析命令行参数
fn parseArgs(allocator: Allocator) !Options {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        print("用法: garlic <输入文件/目录> [选项]\n", .{});
        print("选项:\n", .{});
        print("  -p            仅打印类信息 (类似 javap)\n", .{});
        print("  -o <路径>     输出目录\n", .{});
        print("  -t <数量>     线程数量 (默认: 4)\n", .{});
        print("  -d            调试模式\n", .{});
        print("  -v            详细输出\n", .{});
        std.process.exit(1);
    }

    // 复制input_path字符串以避免内存释放问题
    const input_path_copy = try allocator.dupe(u8, args[1]);

    var options = Options{
        .input_path = input_path_copy,
    };

    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "-p")) {
            options.print_info_only = true;
        } else if (std.mem.eql(u8, arg, "-o") and i + 1 < args.len) {
            i += 1;
            options.output_path = try allocator.dupe(u8, args[i]);
        } else if (std.mem.eql(u8, arg, "-t") and i + 1 < args.len) {
            i += 1;
            options.thread_count = std.fmt.parseInt(u32, args[i], 10) catch {
                print("错误: 无效的线程数量 '{s}'\n", .{args[i]});
                std.process.exit(1);
            };
            // 限制线程数量范围
            if (options.thread_count < 1) options.thread_count = 1;
            if (options.thread_count > 16) options.thread_count = 16;
        } else if (std.mem.eql(u8, arg, "-d")) {
            options.debug_mode = true;
        } else if (std.mem.eql(u8, arg, "-v")) {
            options.verbose = true;
        } else {
            print("错误: 未知选项 '{s}'\n", .{arg});
            std.process.exit(1);
        }
    }

    return options;
}

/// 打印类信息（类似 javap）
fn printClassInfo(class_file: *const parser.ClassFile) !void {
    // 打印类基本信息
    print("Compiled from \"<unknown>.java\"\n", .{});

    // 打印访问标志
    if (class_file.access_flags & 0x0001 != 0) print("public ", .{});
    if (class_file.access_flags & 0x0010 != 0) print("final ", .{});
    if (class_file.access_flags & 0x0020 != 0) print("super ", .{});
    if (class_file.access_flags & 0x0200 != 0) print("interface ", .{});
    if (class_file.access_flags & 0x0400 != 0) print("abstract ", .{});

    // 打印类名
    const class_name = try getClassName(class_file);
    if (class_file.access_flags & 0x0200 != 0) {
        print("interface {s}\n", .{class_name});
    } else {
        print("class {s}\n", .{class_name});
    }

    // 打印版本信息
    print("  minor version: {}\n", .{class_file.minor_version});
    print("  major version: {}\n", .{class_file.major_version});
    print("  flags: 0x{x:0>4}\n", .{class_file.access_flags});

    // 打印常量池
    print("Constant pool:\n", .{});
    for (class_file.constant_pool, 1..) |entry, i| {
        print("  #{}: ", .{i});
        switch (entry) {
            .utf8 => |s| print("Utf8               {s}\n", .{s}),
            .class => |idx| print("Class              #{}\n", .{idx}),
            .string => |idx| print("String             #{}\n", .{idx}),
            .fieldref => |ref| print("Fieldref           #{}.#{}\n", .{ ref.class_index, ref.name_and_type_index }),
            .methodref => |ref| print("Methodref          #{}.#{}\n", .{ ref.class_index, ref.name_and_type_index }),
            .name_and_type => |nt| print("NameAndType        #{}:#{}\n", .{ nt.name_index, nt.descriptor_index }),
            else => print("Other\n", .{}),
        }
    }

    // 打印字段
    if (class_file.fields.len > 0) {
        print("\nFields:\n", .{});
        for (class_file.fields) |field| {
            try printFieldInfo(class_file, &field);
        }
    }

    // 打印方法
    if (class_file.methods.len > 0) {
        print("\nMethods:\n", .{});
        for (class_file.methods) |method| {
            try printMethodInfo(class_file, &method);
        }
    }
}

/// 获取类名
fn getClassName(class_file: *const parser.ClassFile) ![]const u8 {
    if (class_file.this_class == 0 or class_file.this_class > class_file.constant_pool.len) {
        return "<unknown>";
    }

    const class_entry = class_file.constant_pool[class_file.this_class - 1];
    if (class_entry != .class) return "<unknown>";

    const name_index = class_entry.class;
    if (name_index == 0 or name_index > class_file.constant_pool.len) {
        return "<unknown>";
    }

    const name_entry = class_file.constant_pool[name_index - 1];
    if (name_entry != .utf8) return "<unknown>";

    return name_entry.utf8;
}

/// 从完整类名获取简单类名
fn getSimpleClassName(full_name: []const u8) []const u8 {
    var i = full_name.len;
    while (i > 0) {
        i -= 1;
        if (full_name[i] == '/') {
            return full_name[i + 1 ..];
        }
    }
    return full_name;
}

/// 生成字段代码
fn generateField(class_file: *const parser.ClassFile, field: *const parser.FieldInfo, java_code: *std.ArrayList(u8)) !void {
    try java_code.appendSlice("    ");

    // 访问修饰符
    if (field.access_flags & 0x0001 != 0) try java_code.appendSlice("public ");
    if (field.access_flags & 0x0002 != 0) try java_code.appendSlice("private ");
    if (field.access_flags & 0x0004 != 0) try java_code.appendSlice("protected ");
    if (field.access_flags & 0x0008 != 0) try java_code.appendSlice("static ");
    if (field.access_flags & 0x0010 != 0) try java_code.appendSlice("final ");
    if (field.access_flags & 0x0040 != 0) try java_code.appendSlice("volatile ");
    if (field.access_flags & 0x0080 != 0) try java_code.appendSlice("transient ");

    // 字段类型和名称
    const field_type = getFieldType(class_file, field);
    const field_name = getFieldName(class_file, field);

    try java_code.appendSlice(field_type);
    try java_code.appendSlice(" ");
    try java_code.appendSlice(field_name);
    try java_code.appendSlice(";\n");
}

/// 生成方法代码
fn generateMethod(class_file: *const parser.ClassFile, method: *const parser.MethodInfo, java_code: *std.ArrayList(u8)) !void {
    try java_code.appendSlice("\n    ");

    // 访问修饰符
    if (method.access_flags & 0x0001 != 0) try java_code.appendSlice("public ");
    if (method.access_flags & 0x0002 != 0) try java_code.appendSlice("private ");
    if (method.access_flags & 0x0004 != 0) try java_code.appendSlice("protected ");
    if (method.access_flags & 0x0008 != 0) try java_code.appendSlice("static ");
    if (method.access_flags & 0x0010 != 0) try java_code.appendSlice("final ");
    if (method.access_flags & 0x0020 != 0) try java_code.appendSlice("synchronized ");
    if (method.access_flags & 0x0100 != 0) try java_code.appendSlice("native ");
    if (method.access_flags & 0x0400 != 0) try java_code.appendSlice("abstract ");

    // 方法返回类型和名称
    const method_name = getMethodName(class_file, method);

    if (std.mem.eql(u8, method_name, "<init>")) {
        // 构造函数
        const class_name = try getClassName(class_file);
        const simple_name = getSimpleClassName(class_name);
        try java_code.appendSlice(simple_name);
    } else {
        // 普通方法
        const return_type = getMethodReturnType(class_file, method);
        try java_code.appendSlice(return_type);
        try java_code.appendSlice(" ");
        try java_code.appendSlice(method_name);
    }

    try java_code.appendSlice("() {\n");

    // 方法体（简化实现）
    if (method.access_flags & 0x0400 == 0) { // 非抽象方法
        try java_code.appendSlice("        // Method implementation\n");
        const return_type = getMethodReturnType(class_file, method);
        if (!std.mem.eql(u8, return_type, "void") and !std.mem.eql(u8, method_name, "<init>")) {
            if (std.mem.eql(u8, return_type, "int") or std.mem.eql(u8, return_type, "byte") or
                std.mem.eql(u8, return_type, "short") or std.mem.eql(u8, return_type, "char"))
            {
                try java_code.appendSlice("        return 0;\n");
            } else if (std.mem.eql(u8, return_type, "long")) {
                try java_code.appendSlice("        return 0L;\n");
            } else if (std.mem.eql(u8, return_type, "float")) {
                try java_code.appendSlice("        return 0.0f;\n");
            } else if (std.mem.eql(u8, return_type, "double")) {
                try java_code.appendSlice("        return 0.0;\n");
            } else if (std.mem.eql(u8, return_type, "boolean")) {
                try java_code.appendSlice("        return false;\n");
            } else {
                try java_code.appendSlice("        return null;\n");
            }
        }
    }

    try java_code.appendSlice("    }\n");
}

/// 获取字段类型
fn getFieldType(class_file: *const parser.ClassFile, field: *const parser.FieldInfo) []const u8 {
    const descriptor = getUtf8String(class_file, field.descriptor_index) orelse "Object";
    return parseTypeDescriptor(descriptor);
}

/// 获取字段名称
fn getFieldName(class_file: *const parser.ClassFile, field: *const parser.FieldInfo) []const u8 {
    return getUtf8String(class_file, field.name_index) orelse "field";
}

/// 获取方法名称
fn getMethodName(class_file: *const parser.ClassFile, method: *const parser.MethodInfo) []const u8 {
    return getUtf8String(class_file, method.name_index) orelse "method";
}

/// 获取方法返回类型
fn getMethodReturnType(class_file: *const parser.ClassFile, method: *const parser.MethodInfo) []const u8 {
    const descriptor = getUtf8String(class_file, method.descriptor_index) orelse "()V";
    return parseMethodReturnType(descriptor);
}

/// 从常量池获取UTF-8字符串
fn getUtf8String(class_file: *const parser.ClassFile, index: u16) ?[]const u8 {
    if (index == 0 or index > class_file.constant_pool.len) return null;

    const entry = class_file.constant_pool[index - 1];
    if (entry != .utf8) return null;

    return entry.utf8;
}

/// 解析类型描述符
fn parseTypeDescriptor(descriptor: []const u8) []const u8 {
    if (descriptor.len == 0) return "Object";

    switch (descriptor[0]) {
        'B' => return "byte",
        'C' => return "char",
        'D' => return "double",
        'F' => return "float",
        'I' => return "int",
        'J' => return "long",
        'S' => return "short",
        'Z' => return "boolean",
        'V' => return "void",
        'L' => {
            // 对象类型 L<classname>;
            if (descriptor.len > 2 and descriptor[descriptor.len - 1] == ';') {
                const class_name = descriptor[1 .. descriptor.len - 1];
                return getSimpleClassName(class_name);
            }
            return "Object";
        },
        '[' => return "Object[]", // 简化数组类型
        else => return "Object",
    }
}

/// 解析方法返回类型
fn parseMethodReturnType(descriptor: []const u8) []const u8 {
    // 查找 ')' 后的返回类型
    var i: usize = 0;
    while (i < descriptor.len) {
        if (descriptor[i] == ')') {
            if (i + 1 < descriptor.len) {
                return parseTypeDescriptor(descriptor[i + 1 ..]);
            }
            break;
        }
        i += 1;
    }
    return "void";
}

/// 打印字段信息
fn printFieldInfo(class_file: *const parser.ClassFile, field: *const parser.FieldInfo) !void {
    // 打印访问标志
    if (field.access_flags & 0x0001 != 0) print("  public ", .{});
    if (field.access_flags & 0x0002 != 0) print("  private ", .{});
    if (field.access_flags & 0x0004 != 0) print("  protected ", .{});
    if (field.access_flags & 0x0008 != 0) print("  static ", .{});
    if (field.access_flags & 0x0010 != 0) print("  final ", .{});
    if (field.access_flags & 0x0040 != 0) print("  volatile ", .{});
    if (field.access_flags & 0x0080 != 0) print("  transient ", .{});

    // 获取字段名和描述符
    const name = getUtf8String(class_file, field.name_index) orelse "<unknown>";
    const descriptor = getUtf8String(class_file, field.descriptor_index) orelse "<unknown>";

    print("{s} {s};\n", .{ descriptor, name });
}

/// 打印方法信息
fn printMethodInfo(class_file: *const parser.ClassFile, method: *const parser.MethodInfo) !void {
    // 打印访问标志
    if (method.access_flags & 0x0001 != 0) print("  public ", .{});
    if (method.access_flags & 0x0002 != 0) print("  private ", .{});
    if (method.access_flags & 0x0004 != 0) print("  protected ", .{});
    if (method.access_flags & 0x0008 != 0) print("  static ", .{});
    if (method.access_flags & 0x0010 != 0) print("  final ", .{});
    if (method.access_flags & 0x0020 != 0) print("  synchronized ", .{});
    if (method.access_flags & 0x0100 != 0) print("  native ", .{});
    if (method.access_flags & 0x0400 != 0) print("  abstract ", .{});

    // 获取方法名和描述符
    const name = getUtf8String(class_file, method.name_index) orelse "<unknown>";
    const descriptor = getUtf8String(class_file, method.descriptor_index) orelse "<unknown>";

    print("{s} {s};\n", .{ descriptor, name });
}

/// 反编译类文件
fn decompileClass(class_file: *const parser.ClassFile, output_path: []const u8, options: *const Options, allocator: Allocator) !void {
    var java_code = std.ArrayList(u8).init(allocator);
    defer java_code.deinit();

    // 获取类名
    const class_name = try getClassName(class_file);
    const simple_class_name = getSimpleClassName(class_name);

    // 生成类声明
    try java_code.appendSlice("// Decompiled by Garlic\n");

    // 访问修饰符
    if (class_file.access_flags & 0x0001 != 0) try java_code.appendSlice("public ");
    if (class_file.access_flags & 0x0400 != 0) try java_code.appendSlice("abstract ");
    if (class_file.access_flags & 0x0010 != 0) try java_code.appendSlice("final ");

    // 类或接口
    if (class_file.access_flags & 0x0200 != 0) {
        try java_code.appendSlice("interface ");
    } else {
        try java_code.appendSlice("class ");
    }

    try java_code.appendSlice(simple_class_name);
    try java_code.appendSlice(" {\n");

    // 生成字段
    for (class_file.fields) |field| {
        try generateField(class_file, &field, &java_code);
    }

    // 生成方法
    for (class_file.methods) |method| {
        try generateMethod(class_file, &method, &java_code);
    }

    try java_code.appendSlice("}\n");

    // 写入文件
    const output_file = std.fs.cwd().createFile(output_path, .{}) catch |err| {
        print("错误: 无法创建输出文件 {s}: {}\n", .{ output_path, err });
        return;
    };
    defer output_file.close();

    try output_file.writeAll(java_code.items);

    if (options.verbose) {
        print("已保存: {s}\n", .{output_path});
        print("  类名: {s}\n", .{simple_class_name});
        print("  字段数: {}\n", .{class_file.fields_count});
        print("  方法数: {}\n", .{class_file.methods_count});
    }
}

/// 处理单个 Java Class 文件
fn processJavaClass(path: []const u8, options: *const Options, allocator: Allocator) !void {
    if (options.verbose) {
        print("解析 Java Class 文件: {s}\n", .{path});
    }

    // 读取文件内容
    const file_data = std.fs.cwd().readFileAlloc(allocator, path, std.math.maxInt(usize)) catch |err| {
        print("错误: 读取文件失败: {}\n", .{err});
        return;
    };
    defer allocator.free(file_data);

    // 解析 Class 文件
    var class_file = parser.parseClassFile(file_data, allocator) catch |err| {
        print("错误: 解析 Class 文件失败: {}\n", .{err});
        return;
    };
    defer class_file.deinit();

    if (options.print_info_only) {
        // 仅打印类信息
        try printClassInfo(&class_file);
    } else {
        // 生成输出文件路径
        const output_path = if (options.output_path) |output| output else "HelloWorld.java";
        try decompileClass(&class_file, output_path, options, allocator);
    }
}

/// 处理 JAR 文件
fn processJarFile(path: []const u8, options: *const Options, allocator: Allocator) !void {
    if (options.verbose) {
        print("处理 JAR 文件: {s}\n", .{path});
    }

    // 确定输出路径
    const output_path = options.output_path orelse try generateDefaultOutputPath(allocator, path);
    defer if (options.output_path == null) allocator.free(output_path);

    try createOutputDir(output_path);

    print("[Garlic] JAR 文件分析\n", .{});
    print("文件     : {s}\n", .{path});
    print("保存到   : {s}\n", .{output_path});
    print("线程数   : {}\n", .{options.thread_count});

    // 打开 ZIP/JAR 文件
    var zip_reader = ZipReader.open(allocator, path) catch |err| {
        print("错误: 无法打开 JAR 文件: {}\n", .{err});
        return;
    };
    defer zip_reader.close();

    // 处理 JAR 中的每个 Class 文件
    var processed_count: u32 = 0;
    for (zip_reader.entries) |entry| {
        if (std.mem.endsWith(u8, entry.name, ".class")) {
            if (options.verbose) {
                print("处理: {s}\n", .{entry.name});
            }

            // 提取并处理 Class 文件
            try processClassFromJar(&zip_reader, &entry, output_path, options, allocator);
            processed_count += 1;
        }
    }

    print("\n[完成] 处理了 {} 个 Class 文件\n", .{processed_count});
}

/// 从 JAR 中处理单个 Class 文件
fn processClassFromJar(zip_reader: *ZipReader, entry: *const libs.zip.ZipEntry, output_path: []const u8, options: *const Options, allocator: Allocator) !void {
    // 读取 Class 文件数据
    const class_data = try zip_reader.extractFile(entry, allocator);
    defer allocator.free(class_data);

    // 解析 Class 文件
    var class_file = parser.parseClassFile(class_data, allocator) catch |err| {
        if (options.verbose) {
            print("警告: 解析 {s} 失败: {}\n", .{ entry.name, err });
        }
        return;
    };
    defer class_file.deinit();

    if (options.print_info_only) {
        print("\n=== {s} ===\n", .{entry.name});
        try printClassInfo(&class_file);
    } else {
        // 生成输出文件路径
        const java_filename = try std.mem.replaceOwned(u8, allocator, entry.name, ".class", ".java");
        defer allocator.free(java_filename);

        const output_file_path = try std.fs.path.join(allocator, &[_][]const u8{ output_path, java_filename });
        defer allocator.free(output_file_path);

        // 确保输出目录存在
        if (std.fs.path.dirname(output_file_path)) |dir| {
            try createOutputDir(dir);
        }

        // 反编译并保存
        try decompileClass(&class_file, output_file_path, options, allocator);
    }
}

/// 处理单个文件
fn processFile(path: []const u8, options: *const Options, allocator: Allocator) !void {
    const file_type = try detectFileType(path, allocator);

    switch (file_type) {
        .java_class => {
            try processJavaClass(path, options, allocator);
        },
        .jar_archive => {
            try processJarFile(path, options, allocator);
        },
        .dex_file => {
            print("错误: DEX 文件暂不支持\n", .{});
            print("       请联系作者获取支持\n", .{});
        },
        .unknown => {
            print("错误: 文件 {s} 不是有效的 Java Class/JAR/DEX 文件\n", .{path});
            return;
        },
    }
}

/// 主函数
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const options = try parseArgs(allocator);
    defer allocator.free(options.input_path);
    defer if (options.output_path) |output| allocator.free(output);

    if (options.verbose) {
        print("Garlic Java 反编译器 - Zig 实现\n", .{});
        print("输入: {s}\n", .{options.input_path});
        if (options.output_path) |output| {
            print("输出: {s}\n", .{output});
        }
        print("线程数: {}\n", .{options.thread_count});
    }

    // 检查输入路径是文件还是目录
    const stat = std.fs.cwd().statFile(options.input_path) catch |err| {
        print("错误: 无法访问 {s}: {}\n", .{ options.input_path, err });
        std.process.exit(1);
    };

    switch (stat.kind) {
        .file => {
            try processFile(options.input_path, &options, allocator);
        },
        .directory => {
            // TODO: 处理目录
            print("处理目录: {s}\n", .{options.input_path});
        },
        else => {
            print("错误: {s} 不是文件或目录\n", .{options.input_path});
            std.process.exit(1);
        },
    }
}

// 测试
test "basic functionality" {
    const testing = std.testing;
    try testing.expect(true);
}
