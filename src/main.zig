const std = @import("std");
const print = std.debug.print;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const common = @import("common/types.zig");
const libs = @import("libs/mod.zig");
const parser = @import("parser/bytecode.zig");
const decompiler = @import("decompiler/decompiler.zig");
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

    var options = Options{
        .input_path = args[1],
    };

    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "-p")) {
            options.print_info_only = true;
        } else if (std.mem.eql(u8, arg, "-o") and i + 1 < args.len) {
            i += 1;
            options.output_path = args[i];
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

/// 获取 UTF-8 字符串
fn getUtf8String(class_file: *const parser.ClassFile, index: u16) ?[]const u8 {
    if (index == 0 or index > class_file.constant_pool.len) return null;

    const entry = class_file.constant_pool[index - 1];
    if (entry != .utf8) return null;

    return entry.utf8;
}

/// 反编译类文件
fn decompileClass(class_file: *const parser.ClassFile, output_path: []const u8, options: *const Options, allocator: Allocator) !void {
    // 创建反编译选项
    const decompiler_options = decompiler.DecompilerOptions{
        .generate_comments = true,
        .preserve_line_numbers = true,
        .recover_variable_names = true,
        .enable_optimization = true,
        .debug_info = options.debug_mode,
    };

    // 创建反编译器实例
    var decompiler_instance = try decompiler.Decompiler.init(allocator, decompiler_options);
    defer decompiler_instance.deinit();

    // 执行反编译
    var result = decompiler_instance.decompileClass(class_file) catch |err| {
        print("错误: 反编译失败: {}\n", .{err});
        return;
    };
    defer result.deinit(allocator);

    // 写入文件
    const output_file = std.fs.cwd().createFile(output_path, .{}) catch |err| {
        print("错误: 无法创建输出文件 {s}: {}\n", .{ output_path, err });
        return;
    };
    defer output_file.close();

    try output_file.writeAll(result.source_code);

    if (options.verbose) {
        print("已保存: {s}\n", .{output_path});
        print("  处理方法数: {}\n", .{result.stats.methods_processed});
        print("  处理指令数: {}\n", .{result.stats.instructions_processed});
        print("  处理时间: {} ms\n", .{result.stats.processing_time_ms});
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
        // 反编译生成 Java 源码
        try decompileClass(&class_file, path, options, allocator);
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
