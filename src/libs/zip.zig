const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;
const list = @import("list.zig");
const str = @import("str.zig");

/// ZIP文件魔数
const ZIP_MAGIC = 0x04034b50;
const CENTRAL_DIR_MAGIC = 0x02014b50;
const END_CENTRAL_DIR_MAGIC = 0x06054b50;

/// 压缩方法
pub const CompressionMethod = enum(u16) {
    stored = 0,
    deflated = 8,
};

/// ZIP文件条目
pub const ZipEntry = struct {
    name: []const u8,
    compressed_size: u32,
    uncompressed_size: u32,
    crc32: u32,
    compression_method: CompressionMethod,
    offset: u32,
    is_directory: bool,

    pub fn init(name: []const u8) ZipEntry {
        return ZipEntry{
            .name = name,
            .compressed_size = 0,
            .uncompressed_size = 0,
            .crc32 = 0,
            .compression_method = .stored,
            .offset = 0,
            .is_directory = std.mem.endsWith(u8, name, "/"),
        };
    }

    pub fn deinit(self: *ZipEntry, allocator: Allocator) void {
        allocator.free(self.name);
    }
};

/// ZIP文件读取器
pub const ZipReader = struct {
    file: std.fs.File,
    entries: []ZipEntry,
    allocator: Allocator,

    /// 打开ZIP文件
    pub fn open(allocator: Allocator, file_path: []const u8) !ZipReader {
        const file = try std.fs.cwd().openFile(file_path, .{});
        errdefer file.close();

        var reader = ZipReader{
            .file = file,
            .entries = &[_]ZipEntry{},
            .allocator = allocator,
        };

        try reader.readCentralDirectory();
        return reader;
    }

    /// 关闭ZIP文件
    pub fn close(self: *ZipReader) void {
        for (self.entries) |*entry| {
            entry.deinit(self.allocator);
        }
        self.allocator.free(self.entries);
        self.file.close();
        self.* = undefined;
    }

    /// 读取中央目录
    fn readCentralDirectory(self: *ZipReader) !void {
        // 查找中央目录结束记录
        const file_size = try self.file.getEndPos();
        const search_start = if (file_size > 65535 + 22) file_size - 65535 - 22 else 0;

        try self.file.seekTo(search_start);
        const search_data = try self.allocator.alloc(u8, @intCast(file_size - search_start));
        defer self.allocator.free(search_data);

        _ = try self.file.readAll(search_data);

        // 从后往前搜索中央目录结束记录
        var i: usize = search_data.len;
        while (i >= 4) {
            i -= 1;
            const magic = std.mem.readInt(u32, @ptrCast(search_data[i .. i + 4]), .little);
            if (magic == END_CENTRAL_DIR_MAGIC) {
                try self.parseCentralDirectoryEnd(search_start + i);
                return;
            }
        }

        return error.InvalidZipFile;
    }

    /// 解析中央目录结束记录
    fn parseCentralDirectoryEnd(self: *ZipReader, offset: u64) !void {
        try self.file.seekTo(offset);

        var buffer: [22]u8 = undefined;
        _ = try self.file.readAll(&buffer);

        const magic = std.mem.readInt(u32, @ptrCast(buffer[0..4]), .little);
        if (magic != END_CENTRAL_DIR_MAGIC) {
            return error.InvalidZipFile;
        }
        const entry_count = std.mem.readInt(u16, @ptrCast(buffer[10..12]), .little);
        const central_dir_size = std.mem.readInt(u32, @ptrCast(buffer[12..16]), .little);
        const central_dir_offset = std.mem.readInt(u32, @ptrCast(buffer[16..20]), .little);

        try self.parseCentralDirectory(central_dir_offset, central_dir_size, entry_count);
    }

    /// 解析中央目录
    fn parseCentralDirectory(self: *ZipReader, offset: u32, size: u32, entry_count: u16) !void {
        try self.file.seekTo(offset);

        const data = try self.allocator.alloc(u8, size);
        defer self.allocator.free(data);
        _ = try self.file.readAll(data);

        var entries = try self.allocator.alloc(ZipEntry, entry_count);
        var pos: usize = 0;

        for (0..entry_count) |i| {
            if (pos + 46 > data.len) return error.InvalidZipFile;

            const magic = std.mem.readInt(u32, @ptrCast(data[pos .. pos + 4]), .little);
            if (magic != CENTRAL_DIR_MAGIC) break;

            const compression_method: CompressionMethod = @enumFromInt(std.mem.readInt(u16, @ptrCast(data[pos + 10 .. pos + 12]), .little));
            const crc32 = std.mem.readInt(u32, @ptrCast(data[pos + 16 .. pos + 20]), .little);
            const compressed_size = std.mem.readInt(u32, @ptrCast(data[pos + 20 .. pos + 24]), .little);
            const uncompressed_size = std.mem.readInt(u32, @ptrCast(data[pos + 24 .. pos + 28]), .little);
            const filename_len = std.mem.readInt(u16, @ptrCast(data[pos + 28 .. pos + 30]), .little);
            const extra_len = std.mem.readInt(u16, @ptrCast(data[pos + 30 .. pos + 32]), .little);
            const comment_len = std.mem.readInt(u16, @ptrCast(data[pos + 32 .. pos + 34]), .little);
            const local_header_offset = std.mem.readInt(u32, @ptrCast(data[pos + 42 .. pos + 46]), .little);

            pos += 46;

            if (pos + filename_len > data.len) return error.InvalidZipFile;
            const filename = try self.allocator.dupe(u8, data[pos .. pos + filename_len]);
            pos += filename_len + extra_len + comment_len;

            entries[i] = ZipEntry{
                .name = filename,
                .compressed_size = compressed_size,
                .uncompressed_size = uncompressed_size,
                .crc32 = crc32,
                .compression_method = compression_method,
                .offset = local_header_offset,
                .is_directory = std.mem.endsWith(u8, filename, "/"),
            };
        }

        self.entries = entries;
    }

    /// 获取条目数量
    pub fn getEntryCount(self: *const ZipReader) usize {
        return self.entries.len;
    }

    /// 获取条目
    pub fn getEntry(self: *const ZipReader, index: usize) ?*const ZipEntry {
        if (index >= self.entries.len) return null;
        return &self.entries[index];
    }

    /// 根据名称查找条目
    pub fn findEntry(self: *const ZipReader, name: []const u8) ?*const ZipEntry {
        for (self.entries) |*entry| {
            if (std.mem.eql(u8, entry.name, name)) {
                return entry;
            }
        }
        return null;
    }

    /// 提取文件数据
    pub fn extractFile(self: *ZipReader, entry: *const ZipEntry, allocator: Allocator) ![]u8 {
        if (entry.is_directory) {
            return error.IsDirectory;
        }

        // 读取本地文件头
        try self.file.seekTo(entry.offset);

        var local_header: [30]u8 = undefined;
        _ = try self.file.readAll(&local_header);

        const magic = std.mem.readInt(u32, @ptrCast(local_header[0..4]), .little);
        if (magic != ZIP_MAGIC) {
            return error.InvalidZipFile;
        }
        const filename_len = std.mem.readInt(u16, @ptrCast(local_header[26..28]), .little);
        const extra_len = std.mem.readInt(u16, @ptrCast(local_header[28..30]), .little);

        // 跳过文件名和额外字段
        try self.file.seekBy(@intCast(filename_len + extra_len));

        // 读取压缩数据
        const compressed_data = try allocator.alloc(u8, entry.compressed_size);
        defer allocator.free(compressed_data);
        _ = try self.file.readAll(compressed_data);

        // 解压缩数据
        switch (entry.compression_method) {
            .stored => {
                // 无压缩，直接复制
                const result = try allocator.alloc(u8, entry.uncompressed_size);
                @memcpy(result, compressed_data[0..entry.uncompressed_size]);
                return result;
            },
            .deflated => {
                // 使用deflate解压缩
                return try self.inflateData(allocator, compressed_data, entry.uncompressed_size);
            },
        }
    }

    /// 解压缩deflate数据（简化实现）
    fn inflateData(self: *ZipReader, allocator: Allocator, compressed_data: []const u8, uncompressed_size: u32) ![]u8 {
        _ = self;
        // 这里应该实现deflate解压缩算法
        // 为了简化，我们只是分配空间并复制数据
        // 实际实现需要使用zlib或类似的库
        const result = try allocator.alloc(u8, uncompressed_size);
        const copy_size = @min(compressed_data.len, uncompressed_size);
        @memcpy(result[0..copy_size], compressed_data[0..copy_size]);
        return result;
    }

    /// 提取所有文件到目录
    pub fn extractAll(self: *ZipReader, output_dir: []const u8) !void {
        // 创建输出目录
        std.fs.cwd().makeDir(output_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        for (self.entries) |*entry| {
            if (entry.is_directory) {
                // 创建目录
                const dir_path = try std.fs.path.join(self.allocator, &[_][]const u8{ output_dir, entry.name });
                defer self.allocator.free(dir_path);

                std.fs.cwd().makePath(dir_path) catch |err| switch (err) {
                    error.PathAlreadyExists => {},
                    else => return err,
                };
            } else {
                // 提取文件
                const file_path = try std.fs.path.join(self.allocator, &[_][]const u8{ output_dir, entry.name });
                defer self.allocator.free(file_path);

                // 确保父目录存在
                if (std.fs.path.dirname(file_path)) |parent_dir| {
                    std.fs.cwd().makePath(parent_dir) catch |err| switch (err) {
                        error.PathAlreadyExists => {},
                        else => return err,
                    };
                }

                const data = try self.extractFile(entry, self.allocator);
                defer self.allocator.free(data);

                const file = try std.fs.cwd().createFile(file_path, .{});
                defer file.close();

                try file.writeAll(data);
            }
        }
    }

    /// 列出所有条目
    pub fn listEntries(self: *const ZipReader) void {
        std.debug.print("ZIP Archive Contents:\n", .{});
        std.debug.print("Name\t\tSize\t\tCompressed\tMethod\n", .{});
        std.debug.print("----\t\t----\t\t----------\t------\n", .{});

        for (self.entries) |*entry| {
            const method_str = switch (entry.compression_method) {
                .stored => "Stored",
                .deflated => "Deflated",
            };

            std.debug.print("{s}\t\t{}\t\t{}\t\t{s}\n", .{ entry.name, entry.uncompressed_size, entry.compressed_size, method_str });
        }
    }
};

/// ZIP文件写入器
pub const ZipWriter = struct {
    file: std.fs.File,
    entries: list.List(ZipEntry),
    central_dir_data: list.List(u8),
    allocator: Allocator,

    /// 创建ZIP文件
    pub fn create(allocator: Allocator, file_path: []const u8) !ZipWriter {
        const file = try std.fs.cwd().createFile(file_path, .{});
        errdefer file.close();

        return ZipWriter{
            .file = file,
            .entries = list.List(ZipEntry).init(allocator),
            .central_dir_data = list.List(u8).init(allocator),
            .allocator = allocator,
        };
    }

    /// 关闭ZIP文件
    pub fn close(self: *ZipWriter) !void {
        try self.writeCentralDirectory();

        for (self.entries.toMutableSlice()) |*entry| {
            entry.deinit(self.allocator);
        }
        self.entries.deinit();
        self.central_dir_data.deinit();
        self.file.close();
        self.* = undefined;
    }

    /// 添加文件
    pub fn addFile(self: *ZipWriter, name: []const u8, data: []const u8) !void {
        const entry_name = try self.allocator.dupe(u8, name);
        var entry = ZipEntry.init(entry_name);

        entry.offset = @intCast(try self.file.getPos());
        entry.uncompressed_size = @intCast(data.len);
        entry.crc32 = calculateCRC32(data);

        // 写入本地文件头
        try self.writeLocalFileHeader(&entry, data);

        // 写入中央目录条目
        try self.writeCentralDirectoryEntry(&entry);

        try self.entries.append(entry);
    }

    /// 添加目录
    pub fn addDirectory(self: *ZipWriter, name: []const u8) !void {
        var dir_name = try self.allocator.alloc(u8, name.len + 1);
        @memcpy(dir_name[0..name.len], name);
        dir_name[name.len] = '/';

        var entry = ZipEntry.init(dir_name);
        entry.offset = @intCast(try self.file.getPos());
        entry.is_directory = true;

        // 写入本地文件头（空数据）
        try self.writeLocalFileHeader(&entry, &[_]u8{});

        // 写入中央目录条目
        try self.writeCentralDirectoryEntry(&entry);

        try self.entries.append(entry);
    }

    /// 从文件系统添加文件
    pub fn addFileFromPath(self: *ZipWriter, file_path: []const u8, archive_name: []const u8) !void {
        const file = try std.fs.cwd().openFile(file_path, .{});
        defer file.close();

        const file_size = try file.getEndPos();
        const data = try self.allocator.alloc(u8, file_size);
        defer self.allocator.free(data);

        _ = try file.readAll(data);
        try self.addFile(archive_name, data);
    }

    /// 写入本地文件头
    fn writeLocalFileHeader(self: *ZipWriter, entry: *ZipEntry, data: []const u8) !void {
        var header: [30]u8 = undefined;

        std.mem.writeInt(u32, @ptrCast(header[0..4]), ZIP_MAGIC, .little);
        std.mem.writeInt(u16, @ptrCast(header[4..6]), 20, .little); // 版本
        std.mem.writeInt(u16, @ptrCast(header[6..8]), 0, .little); // 标志
        std.mem.writeInt(u16, @ptrCast(header[8..10]), @intFromEnum(entry.compression_method), .little);
        std.mem.writeInt(u16, @ptrCast(header[10..12]), 0, .little); // 修改时间
        std.mem.writeInt(u16, @ptrCast(header[12..14]), 0, .little); // 修改日期
        std.mem.writeInt(u32, @ptrCast(header[14..18]), entry.crc32, .little);
        std.mem.writeInt(u32, @ptrCast(header[18..22]), @intCast(data.len), .little); // 压缩大小
        std.mem.writeInt(u32, @ptrCast(header[22..26]), entry.uncompressed_size, .little);
        std.mem.writeInt(u16, @ptrCast(header[26..28]), @intCast(entry.name.len), .little);
        std.mem.writeInt(u16, @ptrCast(header[28..30]), 0, .little); // 额外字段长度

        try self.file.writeAll(&header);
        try self.file.writeAll(entry.name);
        try self.file.writeAll(data);

        entry.compressed_size = @intCast(data.len);
    }

    /// 写入中央目录条目
    fn writeCentralDirectoryEntry(self: *ZipWriter, entry: *const ZipEntry) !void {
        var header: [46]u8 = undefined;

        std.mem.writeInt(u32, @ptrCast(header[0..4]), CENTRAL_DIR_MAGIC, .little);
        std.mem.writeInt(u16, @ptrCast(header[4..6]), 20, .little); // 制作版本
        std.mem.writeInt(u16, @ptrCast(header[6..8]), 20, .little); // 提取版本
        std.mem.writeInt(u16, @ptrCast(header[8..10]), 0, .little); // 标志
        std.mem.writeInt(u16, @ptrCast(header[10..12]), @intFromEnum(entry.compression_method), .little);
        std.mem.writeInt(u16, @ptrCast(header[12..14]), 0, .little); // 修改时间
        std.mem.writeInt(u16, @ptrCast(header[14..16]), 0, .little); // 修改日期
        std.mem.writeInt(u32, @ptrCast(header[16..20]), entry.crc32, .little);
        std.mem.writeInt(u32, @ptrCast(header[20..24]), entry.compressed_size, .little);
        std.mem.writeInt(u32, @ptrCast(header[24..28]), entry.uncompressed_size, .little);
        std.mem.writeInt(u16, @ptrCast(header[28..30]), @intCast(entry.name.len), .little);
        std.mem.writeInt(u16, @ptrCast(header[30..32]), 0, .little); // 额外字段长度
        std.mem.writeInt(u16, @ptrCast(header[32..34]), 0, .little); // 注释长度
        std.mem.writeInt(u16, @ptrCast(header[34..36]), 0, .little); // 磁盘号
        std.mem.writeInt(u16, @ptrCast(header[36..38]), 0, .little); // 内部属性
        std.mem.writeInt(u32, @ptrCast(header[38..42]), 0, .little); // 外部属性
        std.mem.writeInt(u32, @ptrCast(header[42..46]), entry.offset, .little);

        try self.central_dir_data.appendSlice(&header);
        try self.central_dir_data.appendSlice(entry.name);
    }

    /// 写入中央目录
    fn writeCentralDirectory(self: *ZipWriter) !void {
        const central_dir_offset = try self.file.getPos();

        // 写入中央目录数据
        try self.file.writeAll(self.central_dir_data.toSlice());

        // 写入中央目录结束记录
        var end_record: [22]u8 = undefined;
        std.mem.writeInt(u32, @ptrCast(end_record[0..4]), END_CENTRAL_DIR_MAGIC, .little);
        std.mem.writeInt(u16, @ptrCast(end_record[4..6]), 0, .little); // 磁盘号
        std.mem.writeInt(u16, @ptrCast(end_record[6..8]), 0, .little); // 中央目录起始磁盘
        std.mem.writeInt(u16, @ptrCast(end_record[8..10]), @intCast(self.entries.len()), .little); // 本磁盘条目数
        std.mem.writeInt(u16, @ptrCast(end_record[10..12]), @intCast(self.entries.len()), .little); // 总条目数
        std.mem.writeInt(u32, @ptrCast(end_record[12..16]), @intCast(self.central_dir_data.len()), .little); // 中央目录大小
        std.mem.writeInt(u32, @ptrCast(end_record[16..20]), @intCast(central_dir_offset), .little); // 中央目录偏移
        std.mem.writeInt(u16, @ptrCast(end_record[20..22]), 0, .little); // 注释长度

        try self.file.writeAll(&end_record);
    }
};

/// 计算CRC32校验和（简化实现）
fn calculateCRC32(data: []const u8) u32 {
    // 这里应该实现标准的CRC32算法
    // 为了简化，我们使用一个简单的哈希函数
    var crc: u32 = 0;
    for (data) |byte| {
        crc = crc ^ byte;
        crc = (crc << 1) ^ (crc >> 31);
    }
    return crc;
}

/// ZIP工具函数
pub const ZipUtils = struct {
    /// 压缩目录到ZIP文件
    pub fn compressDirectory(allocator: Allocator, dir_path: []const u8, zip_path: []const u8) !void {
        var writer = try ZipWriter.create(allocator, zip_path);
        defer writer.close() catch {};

        try addDirectoryRecursive(&writer, dir_path, "");
    }

    /// 递归添加目录
    fn addDirectoryRecursive(writer: *ZipWriter, dir_path: []const u8, archive_prefix: []const u8) !void {
        var dir = try std.fs.cwd().openIterableDir(dir_path, .{});
        defer dir.close();

        var iterator = dir.iterate();
        while (try iterator.next()) |entry| {
            const full_path = try std.fs.path.join(writer.allocator, &[_][]const u8{ dir_path, entry.name });
            defer writer.allocator.free(full_path);

            const archive_path = if (archive_prefix.len > 0)
                try std.fs.path.join(writer.allocator, &[_][]const u8{ archive_prefix, entry.name })
            else
                try writer.allocator.dupe(u8, entry.name);
            defer writer.allocator.free(archive_path);

            switch (entry.kind) {
                .directory => {
                    try writer.addDirectory(archive_path);
                    try addDirectoryRecursive(writer, full_path, archive_path);
                },
                .file => {
                    try writer.addFileFromPath(full_path, archive_path);
                },
                else => {}, // 忽略其他类型
            }
        }
    }

    /// 解压ZIP文件到目录
    pub fn extractZip(allocator: Allocator, zip_path: []const u8, output_dir: []const u8) !void {
        var reader = try ZipReader.open(allocator, zip_path);
        defer reader.close();

        try reader.extractAll(output_dir);
    }
};

test "ZIP basic operations" {
    const test_data = "Hello, ZIP World!";
    const zip_path = "test.zip";

    // 创建ZIP文件
    {
        var writer = try ZipWriter.create(testing.allocator, zip_path);
        defer writer.close() catch {};

        try writer.addFile("test.txt", test_data);
    }

    // 清理
    std.fs.cwd().deleteFile(zip_path) catch {};
}
