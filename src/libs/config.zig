const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;
const str = @import("str.zig");
const list = @import("list.zig");
const hashmap = @import("hashmap.zig");

/// 配置值类型
pub const ConfigValue = union(enum) {
    string: []const u8,
    integer: i64,
    float: f64,
    boolean: bool,
    array: []ConfigValue,
    object: hashmap.HashMap([]const u8, ConfigValue),
    null_value,

    /// 释放配置值
    pub fn deinit(self: *ConfigValue, allocator: Allocator) void {
        switch (self.*) {
            .string => |s| allocator.free(s),
            .array => |arr| {
                for (arr) |*item| {
                    item.deinit(allocator);
                }
                allocator.free(arr);
            },
            .object => |*obj| {
                var iterator = obj.iterator();
                while (iterator.next()) |entry| {
                    allocator.free(entry.key);
                    var mutable_value = entry.value;
                    mutable_value.deinit(allocator);
                }
                obj.deinit();
            },
            else => {},
        }
    }

    /// 克隆配置值
    pub fn clone(self: *const ConfigValue, allocator: Allocator) !ConfigValue {
        return switch (self.*) {
            .string => |s| ConfigValue{ .string = try allocator.dupe(u8, s) },
            .integer => |i| ConfigValue{ .integer = i },
            .float => |f| ConfigValue{ .float = f },
            .boolean => |b| ConfigValue{ .boolean = b },
            .null_value => ConfigValue.null_value,
            .array => |arr| {
                const new_arr = try allocator.alloc(ConfigValue, arr.len);
                for (arr, 0..) |*item, i| {
                    new_arr[i] = try item.clone(allocator);
                }
                return ConfigValue{ .array = new_arr };
            },
            .object => |obj| {
                var new_obj = hashmap.HashMap([]const u8, ConfigValue).init(allocator);
                var iterator = obj.iterator();
                while (iterator.next()) |entry| {
                    const key = try allocator.dupe(u8, entry.key);
                    const value = try entry.value.clone(allocator);
                    try new_obj.put(key, value);
                }
                return ConfigValue{ .object = new_obj };
            },
        };
    }

    /// 转换为字符串
    pub fn asString(self: *const ConfigValue) ?[]const u8 {
        return switch (self.*) {
            .string => |s| s,
            else => null,
        };
    }

    /// 转换为整数
    pub fn asInteger(self: *const ConfigValue) ?i64 {
        return switch (self.*) {
            .integer => |i| i,
            .float => |f| @intFromFloat(f),
            else => null,
        };
    }

    /// 转换为浮点数
    pub fn asFloat(self: *const ConfigValue) ?f64 {
        return switch (self.*) {
            .float => |f| f,
            .integer => |i| @floatFromInt(i),
            else => null,
        };
    }

    /// 转换为布尔值
    pub fn asBoolean(self: *const ConfigValue) ?bool {
        return switch (self.*) {
            .boolean => |b| b,
            .string => |s| {
                if (std.mem.eql(u8, s, "true") or std.mem.eql(u8, s, "1")) {
                    return true;
                } else if (std.mem.eql(u8, s, "false") or std.mem.eql(u8, s, "0")) {
                    return false;
                }
                return null;
            },
            .integer => |i| i != 0,
            else => null,
        };
    }

    /// 转换为数组
    pub fn asArray(self: *const ConfigValue) ?[]ConfigValue {
        return switch (self.*) {
            .array => |arr| arr,
            else => null,
        };
    }

    /// 转换为对象
    pub fn asObject(self: *const ConfigValue) ?*const hashmap.HashMap([]const u8, ConfigValue) {
        return switch (self.*) {
            .object => |*obj| obj,
            else => null,
        };
    }

    /// 转换为可变对象
    pub fn asObjectMut(self: *ConfigValue) ?*hashmap.HashMap([]const u8, ConfigValue) {
        return switch (self.*) {
            .object => |*obj| obj,
            else => null,
        };
    }

    /// 检查是否为null
    pub fn isNull(self: *const ConfigValue) bool {
        return switch (self.*) {
            .null_value => true,
            else => false,
        };
    }
};

/// 配置格式
pub const ConfigFormat = enum {
    json,
    ini,
    yaml,
    toml,

    /// 从文件扩展名推断格式
    pub fn fromExtension(ext: []const u8) ?ConfigFormat {
        if (std.mem.eql(u8, ext, ".json")) return .json;
        if (std.mem.eql(u8, ext, ".ini")) return .ini;
        if (std.mem.eql(u8, ext, ".yaml") or std.mem.eql(u8, ext, ".yml")) return .yaml;
        if (std.mem.eql(u8, ext, ".toml")) return .toml;
        return null;
    }
};

/// 配置解析器接口
pub const ConfigParser = struct {
    parse_fn: *const fn (allocator: Allocator, content: []const u8) anyerror!ConfigValue,
    serialize_fn: *const fn (allocator: Allocator, value: *const ConfigValue) anyerror![]u8,

    pub fn parse(self: *const ConfigParser, allocator: Allocator, content: []const u8) !ConfigValue {
        return self.parse_fn(allocator, content);
    }

    pub fn serialize(self: *const ConfigParser, allocator: Allocator, value: *const ConfigValue) ![]u8 {
        return self.serialize_fn(allocator, value);
    }
};

/// JSON解析器
pub const JsonParser = struct {
    pub const parser = ConfigParser{
        .parse_fn = parse,
        .serialize_fn = serialize,
    };

    fn parse(allocator: Allocator, content: []const u8) !ConfigValue {
        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, content, .{});
        defer parsed.deinit();

        return try jsonValueToConfigValue(allocator, parsed.value);
    }

    fn serialize(allocator: Allocator, value: *const ConfigValue) ![]u8 {
        var string = std.ArrayList(u8).init(allocator);
        defer string.deinit();

        try serializeConfigValueToJson(value, string.writer());
        return string.toOwnedSlice();
    }

    fn jsonValueToConfigValue(allocator: Allocator, json_value: std.json.Value) !ConfigValue {
        return switch (json_value) {
            .null => ConfigValue.null_value,
            .bool => |b| ConfigValue{ .boolean = b },
            .integer => |i| ConfigValue{ .integer = i },
            .float => |f| ConfigValue{ .float = f },
            .number_string => |s| {
                // 尝试解析为整数或浮点数
                if (std.fmt.parseInt(i64, s, 10)) |int_val| {
                    return ConfigValue{ .integer = int_val };
                } else |_| {}
                if (std.fmt.parseFloat(f64, s)) |float_val| {
                    return ConfigValue{ .float = float_val };
                } else |_| {}
                // 如果都失败，作为字符串处理
                return ConfigValue{ .string = try allocator.dupe(u8, s) };
            },
            .string => |s| ConfigValue{ .string = try allocator.dupe(u8, s) },
            .array => |arr| {
                const config_arr = try allocator.alloc(ConfigValue, arr.items.len);
                for (arr.items, 0..) |item, i| {
                    config_arr[i] = try jsonValueToConfigValue(allocator, item);
                }
                return ConfigValue{ .array = config_arr };
            },
            .object => |obj| {
                var config_obj = try hashmap.HashMap([]const u8, ConfigValue).init(allocator);
                var iterator = obj.iterator();
                while (iterator.next()) |entry| {
                    const key = try allocator.dupe(u8, entry.key_ptr.*);
                    const value = try jsonValueToConfigValue(allocator, entry.value_ptr.*);
                    try config_obj.put(key, value);
                }
                return ConfigValue{ .object = config_obj };
            },
        };
    }

    fn serializeConfigValueToJson(value: *const ConfigValue, writer: anytype) !void {
        switch (value.*) {
            .null_value => try writer.writeAll("null"),
            .boolean => |b| try writer.writeAll(if (b) "true" else "false"),
            .integer => |i| try writer.print("{}", .{i}),
            .float => |f| try writer.print("{d}", .{f}),
            .string => |s| {
                try writer.writeByte('"');
                for (s) |c| {
                    switch (c) {
                        '"' => try writer.writeAll("\\\""),
                        '\\' => try writer.writeAll("\\\\"),
                        '\n' => try writer.writeAll("\\n"),
                        '\r' => try writer.writeAll("\\r"),
                        '\t' => try writer.writeAll("\\t"),
                        else => try writer.writeByte(c),
                    }
                }
                try writer.writeByte('"');
            },
            .array => |arr| {
                try writer.writeByte('[');
                for (arr, 0..) |*item, i| {
                    if (i > 0) try writer.writeByte(',');
                    try serializeConfigValueToJson(item, writer);
                }
                try writer.writeByte(']');
            },
            .object => |obj| {
                try writer.writeByte('{');
                var iterator = obj.iterator();
                var first = true;
                while (iterator.next()) |entry| {
                    if (!first) try writer.writeByte(',');
                    first = false;

                    try writer.writeByte('"');
                    try writer.writeAll(entry.key);
                    try writer.writeAll("\":");
                    try serializeConfigValueToJson(&entry.value, writer);
                }
                try writer.writeByte('}');
            },
        }
    }
};

/// INI解析器（简化实现）
pub const IniParser = struct {
    pub const parser = ConfigParser{
        .parse_fn = parse,
        .serialize_fn = serialize,
    };

    fn parse(allocator: Allocator, content: []const u8) !ConfigValue {
        var config_obj = try hashmap.HashMap([]const u8, ConfigValue).init(allocator);
        var current_section = try allocator.dupe(u8, "default");
        var section_obj = try hashmap.HashMap([]const u8, ConfigValue).init(allocator);

        var lines = std.mem.splitSequence(u8, content, "\n");
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0 or trimmed[0] == ';' or trimmed[0] == '#') {
                continue; // 空行或注释
            }

            if (trimmed[0] == '[' and trimmed[trimmed.len - 1] == ']') {
                // 新节
                if (section_obj.size > 0) {
                    try config_obj.put(current_section, ConfigValue{ .object = section_obj });
                }
                allocator.free(current_section);
                current_section = try allocator.dupe(u8, trimmed[1 .. trimmed.len - 1]);
                section_obj = try hashmap.HashMap([]const u8, ConfigValue).init(allocator);
            } else if (std.mem.indexOf(u8, trimmed, "=")) |eq_pos| {
                // 键值对
                const key = std.mem.trim(u8, trimmed[0..eq_pos], " \t");
                const value_str = std.mem.trim(u8, trimmed[eq_pos + 1 ..], " \t");

                const key_copy = try allocator.dupe(u8, key);
                const value = try parseIniValue(allocator, value_str);
                try section_obj.put(key_copy, value);
            }
        }

        // 添加最后一个节
        if (section_obj.size > 0) {
            try config_obj.put(current_section, ConfigValue{ .object = section_obj });
        } else {
            allocator.free(current_section);
        }

        return ConfigValue{ .object = config_obj };
    }

    fn parseIniValue(allocator: Allocator, value_str: []const u8) !ConfigValue {
        // 尝试解析为不同类型
        if (std.mem.eql(u8, value_str, "true")) {
            return ConfigValue{ .boolean = true };
        }
        if (std.mem.eql(u8, value_str, "false")) {
            return ConfigValue{ .boolean = false };
        }

        if (std.fmt.parseInt(i64, value_str, 10)) |int_val| {
            return ConfigValue{ .integer = int_val };
        } else |_| {}

        if (std.fmt.parseFloat(f64, value_str)) |float_val| {
            return ConfigValue{ .float = float_val };
        } else |_| {}

        // 默认为字符串
        return ConfigValue{ .string = try allocator.dupe(u8, value_str) };
    }

    fn serialize(allocator: Allocator, value: *const ConfigValue) ![]u8 {
        var result = try str.MutableString.init(allocator);
        defer result.deinit();

        if (value.asObject()) |obj| {
            var iterator = obj.iterator();
            while (iterator.next()) |entry| {
                try result.append("[");
                try result.append(entry.key);
                try result.append("]\n");

                if (entry.value.asObject()) |section_obj| {
                    var section_iter = section_obj.iterator();
                    while (section_iter.next()) |section_entry| {
                        try result.append(section_entry.key);
                        try result.append(" = ");
                        try serializeIniValue(&result, &section_entry.value);
                        try result.append("\n");
                    }
                }
                try result.append("\n");
            }
        }

        return result.toOwnedSlice();
    }

    fn serializeIniValue(result: *str.MutableString, value: *const ConfigValue) !void {
        switch (value.*) {
            .string => |s| try result.append(s),
            .integer => |i| {
                const str_val = try std.fmt.allocPrint(result.allocator, "{}", .{i});
                defer result.allocator.free(str_val);
                try result.append(str_val);
            },
            .float => |f| {
                const str_val = try std.fmt.allocPrint(result.allocator, "{d}", .{f});
                defer result.allocator.free(str_val);
                try result.append(str_val);
            },
            .boolean => |b| try result.append(if (b) "true" else "false"),
            else => try result.append("null"),
        }
    }
};

/// 配置管理器
pub const ConfigManager = struct {
    allocator: Allocator,
    config: ConfigValue,
    parsers: hashmap.HashMap(ConfigFormat, ConfigParser),
    file_path: ?[]const u8,
    auto_save: bool,

    /// 初始化配置管理器
    pub fn init(allocator: Allocator) !ConfigManager {
        var parsers = try hashmap.HashMap(ConfigFormat, ConfigParser).init(allocator);

        // 注册默认解析器
        try parsers.put(.json, JsonParser.parser);
        try parsers.put(.ini, IniParser.parser);

        return ConfigManager{
            .allocator = allocator,
            .config = ConfigValue{ .object = try hashmap.HashMap([]const u8, ConfigValue).init(allocator) },
            .parsers = parsers,
            .file_path = null,
            .auto_save = false,
        };
    }

    /// 释放配置管理器
    pub fn deinit(self: *ConfigManager) void {
        self.config.deinit(self.allocator);
        self.parsers.deinit();
        if (self.file_path) |path| {
            self.allocator.free(path);
        }
        self.* = undefined;
    }

    /// 从文件加载配置
    pub fn loadFromFile(self: *ConfigManager, file_path: []const u8) !void {
        const file = try std.fs.cwd().openFile(file_path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, std.math.maxInt(usize));
        defer self.allocator.free(content);

        // 推断格式
        const ext = std.fs.path.extension(file_path);
        const format = ConfigFormat.fromExtension(ext) orelse .json;

        try self.loadFromString(content, format);

        // 保存文件路径
        if (self.file_path) |old_path| {
            self.allocator.free(old_path);
        }
        self.file_path = try self.allocator.dupe(u8, file_path);
    }

    /// 从字符串加载配置
    pub fn loadFromString(self: *ConfigManager, content: []const u8, format: ConfigFormat) !void {
        const parser = self.parsers.get(format) orelse return error.UnsupportedFormat;

        // 释放旧配置
        self.config.deinit(self.allocator);

        // 解析新配置
        self.config = try parser.parse(self.allocator, content);
    }

    /// 保存配置到文件
    pub fn saveToFile(self: *ConfigManager, file_path: ?[]const u8) !void {
        const path = file_path orelse self.file_path orelse return error.NoFilePath;

        // 推断格式
        const ext = std.fs.path.extension(path);
        const format = ConfigFormat.fromExtension(ext) orelse .json;

        const parser = self.parsers.get(format) orelse return error.UnsupportedFormat;
        const content = try parser.serialize(self.allocator, &self.config);
        defer self.allocator.free(content);

        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        try file.writeAll(content);
    }

    /// 获取配置值
    pub fn get(self: *const ConfigManager, path: []const u8) ?*const ConfigValue {
        return self.getFromValue(&self.config, path);
    }

    /// 从指定值获取路径
    fn getFromValue(self: *const ConfigManager, value: *const ConfigValue, path: []const u8) ?*const ConfigValue {
        if (path.len == 0) return value;

        const dot_pos = std.mem.indexOf(u8, path, ".");
        const key = if (dot_pos) |pos| path[0..pos] else path;
        const remaining = if (dot_pos) |pos| path[pos + 1 ..] else "";

        if (value.asObject()) |obj| {
            if (obj.getPtrConst(key)) |next_value| {
                if (remaining.len == 0) {
                    return next_value;
                } else {
                    return self.getFromValue(next_value, remaining);
                }
            }
        }

        return null;
    }

    /// 设置配置值
    pub fn set(self: *ConfigManager, path: []const u8, value: ConfigValue) !void {
        try self.setInValue(&self.config, path, value);

        if (self.auto_save) {
            try self.saveToFile(null);
        }
    }

    /// 在指定值中设置路径
    fn setInValue(self: *ConfigManager, target_value: *ConfigValue, path: []const u8, value: ConfigValue) !void {
        const dot_pos = std.mem.indexOf(u8, path, ".");
        const key = if (dot_pos) |pos| path[0..pos] else path;
        const remaining = if (dot_pos) |pos| path[pos + 1 ..] else "";

        // 确保目标是对象
        if (target_value.asObject() == null) {
            target_value.deinit(self.allocator);
            target_value.* = ConfigValue{ .object = try hashmap.HashMap([]const u8, ConfigValue).init(self.allocator) };
        }

        var obj = &target_value.object;

        if (remaining.len == 0) {
            // 设置最终值
            // 如果键已存在，释放旧值
            if (obj.getPtr(key)) |old_value| {
                old_value.deinit(self.allocator);
                old_value.* = value;
            } else {
                const key_copy = try self.allocator.dupe(u8, key);
                try obj.put(key_copy, value);
            }
        } else {
            // 递归设置
            if (obj.getPtr(key)) |next_value| {
                try self.setInValue(next_value, remaining, value);
            } else {
                // 创建中间对象
                const key_copy = try self.allocator.dupe(u8, key);
                var intermediate = ConfigValue{ .object = try hashmap.HashMap([]const u8, ConfigValue).init(self.allocator) };
                try self.setInValue(&intermediate, remaining, value);
                try obj.put(key_copy, intermediate);
            }
        }
    }

    /// 删除配置值
    pub fn remove(self: *ConfigManager, path: []const u8) !bool {
        const result = try self.removeFromValue(&self.config, path);

        if (result and self.auto_save) {
            try self.saveToFile(null);
        }

        return result;
    }

    /// 从指定值中删除路径
    fn removeFromValue(self: *ConfigManager, target_value: *ConfigValue, path: []const u8) !bool {
        const dot_pos = std.mem.indexOf(u8, path, ".");
        const key = if (dot_pos) |pos| path[0..pos] else path;
        const remaining = if (dot_pos) |pos| path[pos + 1 ..] else "";

        if (target_value.asObjectMut()) |obj| {
            if (remaining.len == 0) {
                // 删除最终键
                if (obj.getPtr(key)) |value_ptr| {
                    value_ptr.deinit(self.allocator);
                    // 需要找到实际的键来释放内存
                    var iter = obj.iterator();
                    while (iter.next()) |entry| {
                        if (std.mem.eql(u8, entry.key, key)) {
                            const stored_key = entry.key;
                            if (obj.remove(key)) {
                                self.allocator.free(stored_key);
                                return true;
                            }
                            break;
                        }
                    }
                }
            } else {
                // 递归删除
                if (obj.getPtr(key)) |next_value| {
                    return self.removeFromValue(next_value, remaining);
                }
            }
        }

        return false;
    }

    /// 检查路径是否存在
    pub fn has(self: *const ConfigManager, path: []const u8) bool {
        return self.get(path) != null;
    }

    /// 获取字符串值
    pub fn getString(self: *const ConfigManager, path: []const u8, default_value: ?[]const u8) ?[]const u8 {
        if (self.get(path)) |value| {
            return value.asString() orelse default_value;
        }
        return default_value;
    }

    /// 获取整数值
    pub fn getInteger(self: *const ConfigManager, path: []const u8, default_value: i64) i64 {
        if (self.get(path)) |value| {
            return value.asInteger() orelse default_value;
        }
        return default_value;
    }

    /// 获取浮点数值
    pub fn getFloat(self: *const ConfigManager, path: []const u8, default_value: f64) f64 {
        if (self.get(path)) |value| {
            return value.asFloat() orelse default_value;
        }
        return default_value;
    }

    /// 获取布尔值
    pub fn getBoolean(self: *const ConfigManager, path: []const u8, default_value: bool) bool {
        if (self.get(path)) |value| {
            return value.asBoolean() orelse default_value;
        }
        return default_value;
    }

    /// 设置自动保存
    pub fn setAutoSave(self: *ConfigManager, auto_save: bool) void {
        self.auto_save = auto_save;
    }

    /// 合并配置
    pub fn merge(self: *ConfigManager, other: *const ConfigValue) !void {
        try self.mergeValues(&self.config, other);

        if (self.auto_save) {
            try self.saveToFile(null);
        }
    }

    /// 合并两个配置值
    fn mergeValues(self: *ConfigManager, target: *ConfigValue, source: *const ConfigValue) !void {
        if (target.asObject() != null and source.asObject() != null) {
            var target_obj = &target.object;
            const source_obj = source.asObject().?;

            var iterator = source_obj.iterator();
            while (iterator.next()) |entry| {
                const key = entry.key;
                const source_value = &entry.value;

                if (target_obj.getPtr(key)) |target_value| {
                    try self.mergeValues(target_value, source_value);
                } else {
                    const key_copy = try self.allocator.dupe(u8, key);
                    const value_copy = try source_value.clone(self.allocator);
                    try target_obj.put(key_copy, value_copy);
                }
            }
        } else {
            // 替换整个值
            target.deinit(self.allocator);
            target.* = try source.clone(self.allocator);
        }
    }
};

test "ConfigValue operations" {
    var value = ConfigValue{ .string = try testing.allocator.dupe(u8, "test") };
    defer value.deinit(testing.allocator);

    try testing.expect(std.mem.eql(u8, value.asString().?, "test"));
    try testing.expect(value.asInteger() == null);

    var bool_value = ConfigValue{ .boolean = true };
    try testing.expect(bool_value.asBoolean().? == true);
}

test "JSON parser" {
    const json_content = "{\"name\": \"test\", \"value\": 42, \"enabled\": true}";

    var config_value = try JsonParser.parser.parse(testing.allocator, json_content);
    defer config_value.deinit(testing.allocator);

    const obj = config_value.asObject().?;
    try testing.expect(std.mem.eql(u8, obj.get("name").?.asString().?, "test"));
    try testing.expect(obj.get("value").?.asInteger().? == 42);
    try testing.expect(obj.get("enabled").?.asBoolean().? == true);
}

test "ConfigManager basic operations" {
    var manager = try ConfigManager.init(testing.allocator);
    defer manager.deinit();

    // 设置值
    try manager.set("app.name", ConfigValue{ .string = try testing.allocator.dupe(u8, "Garlic") });
    try manager.set("app.version", ConfigValue{ .integer = 1 });
    try manager.set("debug", ConfigValue{ .boolean = true });

    // 获取值
    try testing.expect(std.mem.eql(u8, manager.getString("app.name", "").?, "Garlic"));
    try testing.expect(manager.getInteger("app.version", 0) == 1);
    try testing.expect(manager.getBoolean("debug", false) == true);

    // 检查存在性
    try testing.expect(manager.has("app.name"));
    try testing.expect(!manager.has("nonexistent"));

    // 删除值
    try testing.expect(try manager.remove("debug"));
    try testing.expect(!manager.has("debug"));
}
