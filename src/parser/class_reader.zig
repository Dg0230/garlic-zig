//! Java Class 文件读取器
//! 负责从文件系统或内存中读取 Java Class 文件，处理二进制数据和大端序转换

const std = @import("std");
const bytecode = @import("bytecode.zig");
const constant_pool = @import("constant_pool.zig");
const method = @import("method.zig");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;

/// 类文件信息
const ClassFileInfo = struct {
    file_path: []const u8,
    file_size: u64,
    last_modified: i64,
    checksum: u32, // CRC32 校验和
};

/// 读取统计信息
const ReadStatistics = struct {
    bytes_read: u64,
    read_time_ms: u64,
    parse_time_ms: u64,
    total_classes: u32,
    successful_reads: u32,
    failed_reads: u32,
};

/// 类文件读取器
const ClassFileReader = struct {
    allocator: Allocator,
    statistics: ReadStatistics,
    cache: HashMap([]const u8, bytecode.ClassFile, std.hash_map.StringContext, std.hash_map.default_max_load_percentage), // 文件路径 -> ClassFile 缓存

    /// 创建类文件读取器
    fn init(allocator: Allocator) ClassFileReader {
        return ClassFileReader{
            .allocator = allocator,
            .statistics = ReadStatistics{
                .bytes_read = 0,
                .read_time_ms = 0,
                .parse_time_ms = 0,
                .total_classes = 0,
                .successful_reads = 0,
                .failed_reads = 0,
            },
            .cache = HashMap([]const u8, bytecode.ClassFile, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
        };
    }

    /// 释放资源
    fn deinit(self: *ClassFileReader) void {
        // 清理缓存中的 ClassFile
        var iterator = self.cache.iterator();
        while (iterator.next()) |entry| {
            var class_file = entry.value_ptr.*;
            class_file.deinit();
            self.allocator.free(entry.key_ptr.*);
        }
        self.cache.deinit();
    }

    /// 从文件路径读取 Class 文件
    fn readFromFile(self: *ClassFileReader, file_path: []const u8) !bytecode.ClassFile {
        const start_time = std.time.milliTimestamp();

        // 检查缓存
        if (self.cache.get(file_path)) |cached_class| {
            return cached_class;
        }

        // 打开文件
        const file = std.fs.cwd().openFile(file_path, .{}) catch |err| {
            self.statistics.failed_reads += 1;
            return switch (err) {
                error.FileNotFound => error.ClassFileNotFound,
                error.AccessDenied => error.ClassFileAccessDenied,
                else => error.ClassFileReadError,
            };
        };
        defer file.close();

        // 获取文件信息
        const file_stat = try file.stat();
        if (file_stat.size > std.math.maxInt(u32)) {
            self.statistics.failed_reads += 1;
            return error.ClassFileTooLarge;
        }

        // 读取文件内容
        const file_size = @as(usize, @intCast(file_stat.size));
        const file_data = try self.allocator.alloc(u8, file_size);
        defer self.allocator.free(file_data);

        const bytes_read = try file.readAll(file_data);
        if (bytes_read != file_size) {
            self.statistics.failed_reads += 1;
            return error.IncompleteRead;
        }

        const read_time = std.time.milliTimestamp() - start_time;
        self.statistics.bytes_read += bytes_read;
        self.statistics.read_time_ms += @intCast(read_time);

        // 解析 Class 文件
        const parse_start = std.time.milliTimestamp();
        const class_file = self.parseClassData(file_data) catch |err| {
            self.statistics.failed_reads += 1;
            return err;
        };

        const parse_time = std.time.milliTimestamp() - parse_start;
        self.statistics.parse_time_ms += @intCast(parse_time);
        self.statistics.successful_reads += 1;
        self.statistics.total_classes += 1;

        // 缓存结果
        const cached_path = try self.allocator.dupe(u8, file_path);
        try self.cache.put(cached_path, class_file);

        return class_file;
    }

    /// 从内存数据读取 Class 文件
    fn readFromMemory(self: *ClassFileReader, data: []const u8) !bytecode.ClassFile {
        const start_time = std.time.milliTimestamp();

        const class_file = self.parseClassData(data) catch |err| {
            self.statistics.failed_reads += 1;
            return err;
        };

        const parse_time = std.time.milliTimestamp() - start_time;
        self.statistics.parse_time_ms += @intCast(parse_time);
        self.statistics.successful_reads += 1;
        self.statistics.total_classes += 1;

        return class_file;
    }

    /// 解析 Class 文件数据
    fn parseClassData(self: *ClassFileReader, data: []const u8) !bytecode.ClassFile {
        return bytecode.parseClassFile(data, self.allocator);
    }

    /// 批量读取目录中的所有 Class 文件
    fn readDirectory(self: *ClassFileReader, dir_path: []const u8, recursive: bool) !ArrayList(bytecode.ClassFile) {
        var class_files = ArrayList(bytecode.ClassFile).init(self.allocator);

        try self.readDirectoryRecursive(dir_path, recursive, &class_files);

        return class_files;
    }

    /// 递归读取目录
    fn readDirectoryRecursive(self: *ClassFileReader, dir_path: []const u8, recursive: bool, class_files: *ArrayList(bytecode.ClassFile)) !void {
        var dir = std.fs.cwd().openIterableDir(dir_path, .{}) catch |err| {
            return switch (err) {
                error.FileNotFound => error.DirectoryNotFound,
                error.AccessDenied => error.DirectoryAccessDenied,
                else => error.DirectoryReadError,
            };
        };
        defer dir.close();

        var iterator = dir.iterate();
        while (try iterator.next()) |entry| {
            const full_path = try std.fs.path.join(self.allocator, &[_][]const u8{ dir_path, entry.name });
            defer self.allocator.free(full_path);

            switch (entry.kind) {
                .file => {
                    // 检查是否为 .class 文件
                    if (std.mem.endsWith(u8, entry.name, ".class")) {
                        const class_file = self.readFromFile(full_path) catch |err| {
                            std.debug.print("警告: 无法读取文件 {s}: {}\n", .{ full_path, err });
                            continue;
                        };
                        try class_files.append(class_file);
                    }
                },
                .directory => {
                    if (recursive) {
                        try self.readDirectoryRecursive(full_path, recursive, class_files);
                    }
                },
                else => {}, // 忽略其他类型的文件
            }
        }
    }

    /// 从 JAR 文件读取 Class 文件
    fn readFromJar(self: *ClassFileReader, jar_path: []const u8) !ArrayList(bytecode.ClassFile) {
        // JAR 文件读取功能暂时不可用
        _ = jar_path;
        // JAR 文件读取功能暂时不可用，返回空列表
        return ArrayList(bytecode.ClassFile).init(self.allocator);
    }

    /// 验证 Class 文件完整性
    fn validateClassFile(self: *ClassFileReader, class_file: *const bytecode.ClassFile) !void {
        // 验证魔数
        if (class_file.magic != 0xCAFEBABE) {
            return error.InvalidMagicNumber;
        }

        // 验证版本
        if (class_file.major_version < 45 or class_file.major_version > 65) {
            return error.UnsupportedClassFileVersion;
        }

        // 验证常量池
        var cp_manager = try constant_pool.ConstantPoolManager.init(class_file.constant_pool, self.allocator);
        defer cp_manager.deinit();

        try cp_manager.validateIntegrity();

        // 验证访问标志
        const is_interface = (class_file.access_flags & bytecode.AccessFlags.INTERFACE) != 0;
        if (!bytecode.isValidAccessFlags(class_file.access_flags, is_interface)) {
            return error.InvalidAccessFlags;
        }

        // 验证类索引
        if (class_file.this_class == 0 or class_file.this_class >= class_file.constant_pool_count) {
            return error.InvalidThisClassIndex;
        }

        // 验证父类索引（Object 类除外）
        if (class_file.super_class != 0 and class_file.super_class >= class_file.constant_pool_count) {
            return error.InvalidSuperClassIndex;
        }

        // 验证接口索引
        for (class_file.interfaces) |interface_index| {
            if (interface_index == 0 or interface_index >= class_file.constant_pool_count) {
                return error.InvalidInterfaceIndex;
            }
        }
    }

    /// 获取类文件信息
    fn getClassFileInfo(self: *ClassFileReader, file_path: []const u8) !ClassFileInfo {
        const file = try std.fs.cwd().openFile(file_path, .{});
        defer file.close();

        const stat = try file.stat();

        // 计算文件校验和
        const file_data = try self.allocator.alloc(u8, @intCast(stat.size));
        defer self.allocator.free(file_data);

        _ = try file.readAll(file_data);
        const checksum = std.hash.Crc32.hash(file_data);

        return ClassFileInfo{
            .file_path = file_path,
            .file_size = stat.size,
            .last_modified = stat.mtime,
            .checksum = checksum,
        };
    }

    /// 清理缓存
    fn clearCache(self: *ClassFileReader) void {
        var iterator = self.cache.iterator();
        while (iterator.next()) |entry| {
            var class_file = entry.value_ptr.*;
            class_file.deinit();
            self.allocator.free(entry.key_ptr.*);
        }
        self.cache.clear();
    }

    /// 获取读取统计信息
    fn getStatistics(self: *const ClassFileReader) ReadStatistics {
        return self.statistics;
    }

    /// 重置统计信息
    fn resetStatistics(self: *ClassFileReader) void {
        self.statistics = ReadStatistics{
            .bytes_read = 0,
            .read_time_ms = 0,
            .parse_time_ms = 0,
            .total_classes = 0,
            .successful_reads = 0,
            .failed_reads = 0,
        };
    }

    /// 打印统计信息
    fn printStatistics(self: *const ClassFileReader) void {
        const stats = self.statistics;
        std.debug.print("类文件读取统计:\n", .{});
        std.debug.print("  总类数: {}\n", .{stats.total_classes});
        std.debug.print("  成功读取: {}\n", .{stats.successful_reads});
        std.debug.print("  失败读取: {}\n", .{stats.failed_reads});
        std.debug.print("  读取字节数: {} bytes\n", .{stats.bytes_read});
        std.debug.print("  读取时间: {} ms\n", .{stats.read_time_ms});
        std.debug.print("  解析时间: {} ms\n", .{stats.parse_time_ms});

        if (stats.successful_reads > 0) {
            const avg_read_time = stats.read_time_ms / stats.successful_reads;
            const avg_parse_time = stats.parse_time_ms / stats.successful_reads;
            const avg_file_size = stats.bytes_read / stats.successful_reads;

            std.debug.print("  平均读取时间: {} ms\n", .{avg_read_time});
            std.debug.print("  平均解析时间: {} ms\n", .{avg_parse_time});
            std.debug.print("  平均文件大小: {} bytes\n", .{avg_file_size});
        }
    }
};

/// 二进制数据读取器（用于更精细的控制）
const BinaryReader = struct {
    data: []const u8,
    pos: usize,

    /// 创建二进制读取器
    fn init(data: []const u8) BinaryReader {
        return BinaryReader{
            .data = data,
            .pos = 0,
        };
    }

    /// 检查是否还有数据可读
    fn hasMore(self: *const BinaryReader) bool {
        return self.pos < self.data.len;
    }

    /// 获取剩余字节数
    fn remaining(self: *const BinaryReader) usize {
        return self.data.len - self.pos;
    }

    /// 跳过指定字节数
    fn skip(self: *BinaryReader, bytes: usize) !void {
        if (self.pos + bytes > self.data.len) {
            return error.UnexpectedEndOfFile;
        }
        self.pos += bytes;
    }

    /// 读取 u8
    fn readU8(self: *BinaryReader) !u8 {
        if (self.pos >= self.data.len) {
            return error.UnexpectedEndOfFile;
        }
        const value = self.data[self.pos];
        self.pos += 1;
        return value;
    }

    /// 读取 i8
    fn readI8(self: *BinaryReader) !i8 {
        return @bitCast(try self.readU8());
    }

    /// 读取 u16 (大端序)
    fn readU16BE(self: *BinaryReader) !u16 {
        if (self.pos + 2 > self.data.len) {
            return error.UnexpectedEndOfFile;
        }
        const value = std.mem.readInt(u16, self.data[self.pos .. self.pos + 2][0..2], .big);
        self.pos += 2;
        return value;
    }

    /// 读取 i16 (大端序)
    fn readI16BE(self: *BinaryReader) !i16 {
        return @bitCast(try self.readU16BE());
    }

    /// 读取 u32 (大端序)
    fn readU32BE(self: *BinaryReader) !u32 {
        if (self.pos + 4 > self.data.len) {
            return error.UnexpectedEndOfFile;
        }
        const value = std.mem.readInt(u32, self.data[self.pos .. self.pos + 4][0..4], .big);
        self.pos += 4;
        return value;
    }

    /// 读取 i32 (大端序)
    fn readI32BE(self: *BinaryReader) !i32 {
        return @bitCast(try self.readU32BE());
    }

    /// 读取 u64 (大端序)
    fn readU64BE(self: *BinaryReader) !u64 {
        if (self.pos + 8 > self.data.len) {
            return error.UnexpectedEndOfFile;
        }
        const value = std.mem.readInt(u64, self.data[self.pos .. self.pos + 8][0..8], .big);
        self.pos += 8;
        return value;
    }

    /// 读取 i64 (大端序)
    fn readI64BE(self: *BinaryReader) !i64 {
        return @bitCast(try self.readU64BE());
    }

    /// 读取 f32 (大端序)
    fn readF32BE(self: *BinaryReader) !f32 {
        const bits = try self.readU32BE();
        return @bitCast(bits);
    }

    /// 读取 f64 (大端序)
    fn readF64BE(self: *BinaryReader) !f64 {
        const bits = try self.readU64BE();
        return @bitCast(bits);
    }

    /// 读取指定长度的字节数组
    fn readBytes(self: *BinaryReader, length: usize, allocator: Allocator) ![]u8 {
        if (self.pos + length > self.data.len) {
            return error.UnexpectedEndOfFile;
        }

        const bytes = try allocator.alloc(u8, length);
        @memcpy(bytes, self.data[self.pos .. self.pos + length]);
        self.pos += length;
        return bytes;
    }

    /// 读取 UTF-8 字符串（带长度前缀）
    fn readUtf8String(self: *BinaryReader, allocator: Allocator) ![]u8 {
        const length = try self.readU16BE();
        return self.readBytes(length, allocator);
    }

    /// 获取当前位置
    fn getPosition(self: *const BinaryReader) usize {
        return self.pos;
    }

    /// 设置位置
    fn setPosition(self: *BinaryReader, pos: usize) !void {
        if (pos > self.data.len) {
            return error.InvalidPosition;
        }
        self.pos = pos;
    }

    /// 对齐到指定字节边界
    fn alignTo(self: *BinaryReader, alignment: usize) void {
        const remainder = self.pos % alignment;
        if (remainder != 0) {
            self.pos += alignment - remainder;
        }
    }
};

/// 创建类文件读取器
fn createClassFileReader(allocator: Allocator) ClassFileReader {
    return ClassFileReader.init(allocator);
}

/// 验证文件是否为有效的 Java Class 文件
fn isValidClassFile(file_path: []const u8) bool {
    const file = std.fs.cwd().openFile(file_path, .{}) catch return false;
    defer file.close();

    var magic_bytes: [4]u8 = undefined;
    const bytes_read = file.readAll(&magic_bytes) catch return false;

    if (bytes_read != 4) return false;

    const magic = std.mem.readInt(u32, &magic_bytes, .big);
    return magic == 0xCAFEBABE;
}

// 导出公共接口
const exports = struct {
    const ClassFileReader = @This().ClassFileReader;
    const BinaryReader = @This().BinaryReader;
    const ClassFileInfo = @This().ClassFileInfo;
    const ReadStatistics = @This().ReadStatistics;
    const createClassFileReader = @This().createClassFileReader;
    const isValidClassFile = @This().isValidClassFile;
};

test "类文件读取器基础功能测试" {
    const testing = std.testing;

    var reader = ClassFileReader.init(testing.allocator);
    defer reader.deinit();

    // 测试统计信息初始化
    const stats = reader.getStatistics();
    try testing.expectEqual(@as(u64, 0), stats.bytes_read);
    try testing.expectEqual(@as(u32, 0), stats.total_classes);
    try testing.expectEqual(@as(u32, 0), stats.successful_reads);
    try testing.expectEqual(@as(u32, 0), stats.failed_reads);
}

test "二进制读取器测试" {
    const testing = std.testing;

    // 创建测试数据
    const test_data = [_]u8{
        0xCA, 0xFE, 0xBA, 0xBE, // u32: 0xCAFEBABE
        0x00, 0x34, // u16: 52
        0x12, // u8: 18
        0xFF, // i8: -1
    };

    var reader = BinaryReader.init(&test_data);

    // 测试读取各种类型
    try testing.expectEqual(@as(u32, 0xCAFEBABE), try reader.readU32BE());
    try testing.expectEqual(@as(u16, 52), try reader.readU16BE());
    try testing.expectEqual(@as(u8, 18), try reader.readU8());
    try testing.expectEqual(@as(i8, -1), try reader.readI8());

    // 测试边界检查
    try testing.expectError(error.UnexpectedEndOfFile, reader.readU8());
}

test "Class 文件验证测试" {
    const testing = std.testing;

    // 注意：这个测试需要实际的 .class 文件才能运行
    // 在实际环境中，可以创建一个简单的测试 .class 文件

    // 测试无效文件路径
    try testing.expect(!isValidClassFile("nonexistent.class"));
}
