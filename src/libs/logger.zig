const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;
const str = @import("str.zig");
const list = @import("list.zig");
const MAX_TARGETS = 10; // Define a maximum number of targets

/// 日志级别
pub const LogLevel = enum(u8) {
    trace = 0,
    debug = 1,
    info = 2,
    warn = 3,
    err = 4,
    fatal = 5,

    /// 获取级别名称
    pub fn name(self: LogLevel) []const u8 {
        return switch (self) {
            .trace => "TRACE",
            .debug => "DEBUG",
            .info => "INFO",
            .warn => "WARN",
            .err => "ERROR",
            .fatal => "FATAL",
        };
    }

    /// 获取级别颜色代码（ANSI）
    pub fn color(self: LogLevel) []const u8 {
        return switch (self) {
            .trace => "\x1b[37m", // 白色
            .debug => "\x1b[36m", // 青色
            .info => "\x1b[32m", // 绿色
            .warn => "\x1b[33m", // 黄色
            .err => "\x1b[31m", // 红色
            .fatal => "\x1b[35m", // 紫色
        };
    }
};

/// 日志目标类型
pub const LogTarget = union(enum) {
    console: struct {
        use_color: bool = true,
    },
    // file: FileLogTarget, // Temporarily commented out
};

/// 文件日志目标（暂时注释掉）
// pub const FileLogTarget = struct {
//     path: []const u8,
//     file: ?std.fs.File = null,
//     max_size: u64 = 10 * 1024 * 1024, // 10MB
//     rotate_count: u32 = 5,
// };

/// 日志格式化器
pub const LogFormatter = struct {
    include_timestamp: bool = true,
    include_level: bool = true,
    include_location: bool = false,
    timestamp_format: []const u8 = "%Y-%m-%d %H:%M:%S",

    /// 格式化日志消息
    pub fn format(self: *const LogFormatter, allocator: Allocator, level: LogLevel, location: ?[]const u8, message: []const u8) !std.ArrayList(u8) {
        var result = std.ArrayList(u8).init(allocator);
        errdefer result.deinit();

        // 添加时间戳
        if (self.include_timestamp) {
            const timestamp = try self.formatTimestamp(allocator);
            defer allocator.free(timestamp);
            try result.appendSlice("[");
            try result.appendSlice(timestamp);
            try result.appendSlice("] ");
        }

        // 添加日志级别
        if (self.include_level) {
            try result.appendSlice("[");
            try result.appendSlice(level.name());
            try result.appendSlice("] ");
        }

        // 添加位置信息
        if (self.include_location and location != null) {
            try result.appendSlice("[");
            try result.appendSlice(location.?);
            try result.appendSlice("] ");
        }

        // 添加消息
        try result.appendSlice(message);

        return result;
    }

    /// 格式化时间戳
    fn formatTimestamp(self: *const LogFormatter, allocator: Allocator) ![]u8 {
        _ = self; // 暂时忽略格式化选项

        const timestamp = std.time.timestamp();
        const seconds_since_epoch: u64 = @intCast(timestamp);

        // 简单的时间格式化（UTC）
        const seconds_per_day = 24 * 60 * 60;
        const days_since_epoch = seconds_since_epoch / seconds_per_day;
        const seconds_today = seconds_since_epoch % seconds_per_day;

        const hours = seconds_today / 3600;
        const minutes = (seconds_today % 3600) / 60;
        const seconds = seconds_today % 60;

        // 简化的日期计算（从1970年开始）
        const year = 1970 + days_since_epoch / 365; // 简化计算
        const month = 1 + (days_since_epoch % 365) / 30; // 简化计算
        const day = 1 + (days_since_epoch % 365) % 30; // 简化计算

        return std.fmt.allocPrint(allocator, "{:04}-{:02}-{:02} {:02}:{:02}:{:02}", .{ year, month, day, hours, minutes, seconds });
    }
};

/// 日志过滤器
pub const LogFilter = struct {
    min_level: LogLevel = .trace,
    allowed_modules: ?[]const []const u8 = null,
    blocked_modules: ?[]const []const u8 = null,

    /// 检查是否应该记录日志
    pub fn shouldLog(self: *const LogFilter, level: LogLevel, module: ?[]const u8) bool {
        // 检查日志级别
        if (@intFromEnum(level) < @intFromEnum(self.min_level)) {
            return false;
        }

        // 检查模块过滤
        if (module) |mod| {
            // 检查阻止列表
            if (self.blocked_modules) |blocked| {
                for (blocked) |blocked_mod| {
                    if (std.mem.eql(u8, mod, blocked_mod)) {
                        return false;
                    }
                }
            }

            // 检查允许列表
            if (self.allowed_modules) |allowed| {
                for (allowed) |allowed_mod| {
                    if (std.mem.eql(u8, mod, allowed_mod)) {
                        return true;
                    }
                }
                return false; // 如果有允许列表但模块不在其中
            }
        }

        return true;
    }
};

/// 日志记录器
pub const Logger = struct {
    allocator: Allocator,
    targets: [MAX_TARGETS]LogTarget,
    target_count: usize,
    formatter: LogFormatter,
    filter: LogFilter,
    mutex: std.Thread.Mutex,

    /// 初始化日志记录器
    pub fn init(allocator: Allocator) Logger {
        std.debug.print("Logger.init: creating logger struct\n", .{});

        const mtx = std.Thread.Mutex{};

        const result = Logger{
            .allocator = allocator,
            .targets = undefined, // Will be initialized as needed
            .target_count = 0,
            .formatter = LogFormatter{},
            .filter = LogFilter{},
            .mutex = mtx,
        };
        std.debug.print("Logger.init: logger struct created\n", .{});
        return result;
    }

    /// Deinitializes the logger, freeing any allocated resources.
    /// This includes closing any open file targets, destroying the formatter, and deinitializing the targets list.
    pub fn deinit(self: *Logger) void {
        std.debug.print("Logger.deinit: starting deinit\n", .{});

        // Close any open file targets
        // Note: Since LogTarget.file is commented out, we skip file cleanup for now
        // if (self.targets) |targets| {
        //     for (targets.items) |*target| {
        //         if (target.* == .file and target.file.file != null) {
        //             target.file.file.?.close();
        //         }
        //     }
        // }

        std.debug.print("Logger.deinit: processing fixed array targets. Count: {}\n", .{self.target_count});
        var i: usize = 0;
        while (i < self.target_count) : (i += 1) {
            std.debug.print("Logger.deinit: processing target {}\n", .{i});
            // if (self.targets[i] == .file) {
            //     std.debug.print("Logger.deinit: closing file target\n", .{});
            //     if (self.targets[i].file.file) |f| {
            //         f.close();
            //         // self.targets[i].file.file = null;
            //     }
            // }
        }

        // self.allocator.destroy(&self.formatter); // formatter is not a pointer
        self.target_count = 0; // Reset target count
        std.debug.print("Logger.deinit: deinit completed\n", .{});
    }

    /// 添加输出目标
    pub fn addTarget(self: *Logger, target: LogTarget) !void {
        if (self.target_count >= MAX_TARGETS) {
            return error.TooManyTargets;
        }

        // Store the target in the fixed array
        self.targets[self.target_count] = target;
        self.target_count += 1;

        std.debug.print("Logger.addTarget: target added. Total count: {}\n", .{self.target_count});

        // If the target is a file target, open the file (logic remains commented out as LogTarget.file is commented)
        // if (target == .file) {
        //     const file_target = &self.targets[self.target_count - 1].file;
        //     file_target.file = try std.fs.cwd().createFile(
        //         file_target.path,
        //         .{ .read = false, .truncate = false },
        //     );
        //
        //     // 如果文件已存在，移动到末尾
        //     try file_target.file.?.seekFromEnd(0);
        // }

        std.debug.print("Logger.addTarget: target setup completed\n", .{});
    }

    /// 设置最小日志级别
    pub fn setMinLevel(self: *Logger, level: LogLevel) void {
        self.filter.min_level = level;
    }

    /// 设置格式化器
    pub fn setFormatter(self: *Logger, formatter: LogFormatter) void {
        self.formatter = formatter;
    }

    /// 记录日志
    pub fn log(self: *Logger, level: LogLevel, comptime format: []const u8, args: anytype) void {
        std.debug.print("Logger.log: ENTRY\n", .{});
        std.debug.print("Logger.log: About to call logWithLocation\n", .{});

        // 调用原始版本
        self.logWithLocation(level, null, format, args);

        std.debug.print("Logger.log: After calling logWithLocation\n", .{});
    }

    /// 简化版本的带位置信息日志记录（用于调试）
    fn logWithLocationSimple(self: *Logger, level: LogLevel, location: ?[]const u8, message: []const u8) void {
        _ = self;
        _ = location;
        std.debug.print("Logger.logWithLocationSimple: ENTRY - level: {s}, message: {s}\n", .{ level.name(), message });
    }

    /// 记录带位置信息的日志
    pub fn logWithLocation(self: *Logger, level: LogLevel, location: ?[]const u8, comptime format: []const u8, args: anytype) void {
        std.debug.print("Logger.logWithLocation: ENTRY\n", .{});

        // 检查过滤器
        // if (!self.filter.shouldLog(level, null)) {
        //     return;
        // }
        std.debug.print("Logger.logWithLocation: After filter check\n", .{});

        // 格式化消息
        const message = std.fmt.allocPrint(self.allocator, format, args) catch |alloc_err| {
            std.debug.print("Logger.logWithLocation: Failed to format message: {any}\n", .{alloc_err});
            self.writeToTargets(level, "[LOG ERROR] Failed to format message");
            return;
        };
        defer self.allocator.free(message);

        // 格式化完整日志
        var formatted_str = self.formatter.format(self.allocator, level, location, message) catch |format_err| {
            std.debug.print("Logger.logWithLocation: Failed to format log: {any}\n", .{format_err});
            self.writeToTargets(level, message);
            return;
        };
        defer formatted_str.deinit();

        std.debug.print("Logger.logWithLocation: About to call writeToTargets\n", .{});
        self.writeToTargets(level, formatted_str.items);
    }

    /// 写入到所有目标
    fn writeToTargets(self: *Logger, level: LogLevel, message: []const u8) void {
        std.debug.print("Logger.writeToTargets: ENTRY\n", .{});

        self.mutex.lock();
        defer self.mutex.unlock();

        var i: usize = 0;
        while (i < self.target_count) : (i += 1) {
            self.writeToTarget(&self.targets[i], level, message);
        }
    }

    /// 写入到单个目标
    fn writeToTarget(self: *Logger, target: *LogTarget, level: LogLevel, message: []const u8) void {
        _ = self;

        switch (target.*) {
            .console => |console_target| {
                if (console_target.use_color) {
                    _ = std.io.getStdOut().writer().print("{s}{s}{s}\n", .{ level.color(), message, "\x1b[0m" }) catch |e| {
                        std.debug.print("Error writing to console: {any}\n", .{e});
                    };
                } else {
                    _ = std.io.getStdOut().writer().print("{s}\n", .{message}) catch |e| {
                        std.debug.print("Error writing to console: {any}\n", .{e});
                    };
                }
            },
            // .file => |*file_target| { // Temporarily commented out
            //     // 省略文件输出逻辑...
            //     if (file_target.file) |f| {
            //         try f.writer().print("{s}\n", .{formatted_message.toSlice()});
            //     } else {
            //         // 文件未打开，可以尝试重新打开或记录错误
            //         std.debug.print("Error: File target not open for path: {s}\n", .{file_target.path});
            //     }
            // },
            // .custom => |custom_target| { // Temporarily commented out
            //     // 调用自定义输出函数
            //     custom_target.write_fn(formatted_message.toSlice());
            // },
        }
    }

    /// 便捷方法：记录debug级别日志
    pub fn debug(self: *Logger, comptime format: []const u8, args: anytype) void {
        self.log(.debug, format, args);
    }

    /// 便捷方法：记录info级别日志
    pub fn info(self: *Logger, comptime format: []const u8, args: anytype) void {
        const message = std.fmt.allocPrint(self.allocator, format, args) catch |alloc_err| {
            std.debug.print("Logger.info: Failed to allocPrint: {any}\n", .{alloc_err});
            return;
        };
        defer self.allocator.free(message);
        std.debug.print("Logger.info (Restored Signature): Formatted message: {s}\n", .{message});
        self.log(.info, format, args);
    }

    /// 便捷方法：记录warn级别日志
    pub fn warn(self: *Logger, comptime format: []const u8, args: anytype) void {
        self.log(.warn, format, args);
    }

    /// 便捷方法：记录error级别日志
    pub fn err(self: *Logger, comptime format: []const u8, args: anytype) void {
        self.log(.err, format, args);
    }

    /// 便捷方法：记录fatal级别日志
    pub fn fatal(self: *Logger, comptime format: []const u8, args: anytype) void {
        self.log(.fatal, format, args);
    }
};

/// 全局日志记录器实例
var global_logger: ?*Logger = null;
var global_allocator: ?Allocator = null;

/// 初始化全局日志记录器
pub fn initGlobal(allocator: Allocator) !void {
    if (global_logger == null) {
        global_allocator = allocator;
        const logger = try allocator.create(Logger);
        logger.* = Logger.init(allocator);
        global_logger = logger;

        // 默认添加控制台输出
        try global_logger.?.addTarget(.{ .console = .{ .use_color = true } });
    }
}

/// 获取全局日志记录器
pub fn getGlobal() ?*Logger {
    if (global_logger) |logger| {
        return logger;
    }
    return null;
}

/// 清理全局日志记录器
pub fn deinitGlobal() void {
    if (global_logger) |logger| {
        logger.deinit();
        if (global_allocator) |allocator| {
            allocator.destroy(logger);
        }
        global_logger = null;
    }
}

/// 全局日志函数
pub fn log(level: LogLevel, comptime format: []const u8, args: anytype) void {
    if (getGlobal()) |logger| {
        logger.log(level, format, args);
    }
}

/// 全局debug日志
pub fn debug(comptime format: []const u8, args: anytype) void {
    log(.debug, format, args);
}

/// 全局info日志
pub fn info(comptime format: []const u8, args: anytype) void {
    log(.info, format, args);
}

/// 全局warn日志
pub fn warn(comptime format: []const u8, args: anytype) void {
    log(.warn, format, args);
}

/// 全局error日志
pub fn err(comptime format: []const u8, args: anytype) void {
    log(.err, format, args);
}

/// 全局fatal日志
pub fn fatal(comptime format: []const u8, args: anytype) void {
    log(.fatal, format, args);
}

/// 全局带位置信息的日志函数
pub fn logWithLocation(level: LogLevel, location: ?[]const u8, comptime format: []const u8, args: anytype) void {
    if (getGlobal()) |logger| {
        logger.logWithLocation(level, location, format, args);
    }
}

test "Logger basic functionality" {
    std.debug.print("Test 'Logger basic functionality': Starting test\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Test 'Logger basic functionality': Creating logger\n", .{});
    var logger = Logger.init(allocator);
    defer {
        std.debug.print("Test 'Logger basic functionality': Calling logger.deinit()\n", .{});
        logger.deinit();
        std.debug.print("Test 'Logger basic functionality': logger.deinit() finished\n", .{});
    }

    // 添加控制台输出目标
    try logger.addTarget(.{ .console = .{ .use_color = false } });
    std.debug.print("Test 'Logger basic functionality': Console target added\n", .{});

    // 测试简化版本的日志记录
    logger.log(.info, "Test message: {s} {d}", .{ "hello", 42 });
    std.debug.print("Test 'Logger basic functionality': Log message sent\n", .{});

    std.debug.print("Test 'Logger basic functionality': Test completed\n", .{});
}
