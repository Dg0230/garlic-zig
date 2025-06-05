//! 基础设施库模块
//! 提供内存管理、数据结构、工具函数等基础功能

// 内存管理
pub const memory = @import("memory.zig");
pub const MemoryPool = memory.MemoryPool;
pub const MemoryPoolAllocator = memory.MemoryPoolAllocator;

// 数据结构
pub const list = @import("list.zig");
pub const List = list.List;
pub const StringList = list.StringList;
pub const IntList = list.IntList;
pub const ObjectList = list.ObjectList;

pub const hashmap = @import("hashmap.zig");
pub const HashMap = hashmap.HashMap;
pub const StringIntMap = hashmap.StringIntMap;
pub const IntStringMap = hashmap.IntStringMap;
pub const StringObjectMap = hashmap.StringObjectMap;

pub const queue = @import("queue.zig");
pub const Queue = queue.Queue;
pub const Deque = queue.Deque;
pub const PriorityQueue = queue.PriorityQueue;
pub const IntQueue = queue.IntQueue;
pub const StringQueue = queue.StringQueue;
pub const ObjectQueue = queue.ObjectQueue;
pub const IntDeque = queue.IntDeque;
pub const StringDeque = queue.StringDeque;
pub const MaxPriorityQueue = queue.MaxPriorityQueue;
pub const MinPriorityQueue = queue.MinPriorityQueue;

pub const bitset = @import("bitset.zig");
pub const BitSet = bitset.BitSet;

pub const trie = @import("trie.zig");
pub const Trie = trie.Trie;

// 字符串处理
pub const str = @import("str.zig");
pub const MutableString = str.MutableString;
pub const StringUtils = str.StringUtils;

// 并发
pub const threadpool = @import("threadpool.zig");
pub const ThreadPool = threadpool.ThreadPool;
pub const BatchExecutor = threadpool.BatchExecutor;
pub const Task = threadpool.Task;
pub const Worker = threadpool.Worker;

// 文件处理
pub const zip = @import("zip.zig");
pub const ZipReader = zip.ZipReader;
pub const ZipWriter = zip.ZipWriter;
pub const ZipEntry = zip.ZipEntry;
pub const ZipUtils = zip.ZipUtils;
pub const CompressionMethod = zip.CompressionMethod;

// 日志系统
pub const logger = @import("logger.zig");
pub const Logger = logger.Logger;
pub const LogLevel = logger.LogLevel;
pub const LogTarget = logger.LogTarget;
pub const LogFormatter = logger.LogFormatter;
pub const LogFilter = logger.LogFilter;

// 全局日志函数
pub const initGlobalLogger = logger.initGlobalLogger;
pub const getGlobalLogger = logger.getGlobalLogger;
pub const deinitGlobalLogger = logger.deinitGlobalLogger;
pub const log = logger.log;
pub const trace = logger.trace;
pub const debug = logger.debug;
pub const info = logger.info;
pub const warn = logger.warn;
pub const err = logger.err;
pub const fatal = logger.fatal;
pub const traceHere = logger.traceHere;
pub const debugHere = logger.debugHere;
pub const infoHere = logger.infoHere;
pub const warnHere = logger.warnHere;
pub const errHere = logger.errHere;
pub const fatalHere = logger.fatalHere;

// 配置管理
pub const config = @import("config.zig");
pub const ConfigManager = config.ConfigManager;
pub const ConfigValue = config.ConfigValue;
pub const ConfigFormat = config.ConfigFormat;
pub const ConfigParser = config.ConfigParser;
pub const JsonParser = config.JsonParser;
pub const IniParser = config.IniParser;

// 测试所有模块
const std = @import("std");
const testing = std.testing;

test "libs module imports" {
    // 测试所有模块是否能正确导入
    _ = memory;
    _ = list;
    _ = hashmap;
    _ = queue;
    _ = bitset;
    _ = trie;
    _ = str;
    _ = threadpool;
    _ = zip;
    _ = logger;
    _ = config;
}

test "basic functionality" {
    // 测试基本功能
    const allocator = testing.allocator;

    // 测试内存池
    var pool = MemoryPool.init(allocator);
    defer pool.deinit();

    const ptr = try pool.alloc(100, @alignOf(u8));
    _ = ptr; // 内存池在 deinit 时统一释放

    // 测试列表
    var int_list = IntList.init(allocator);
    defer int_list.deinit();

    try int_list.append(42);
    try testing.expect(int_list.get(0) == 42);

    // 测试哈希表
    var string_map = try StringIntMap.init(allocator);
    defer string_map.deinit();

    try string_map.put("test", 123);
    try testing.expect(string_map.get("test").? == 123);

    // 测试字符串
    var mutable_str = try MutableString.init(allocator);
    defer mutable_str.deinit();

    try mutable_str.append("Hello");
    try mutable_str.append(" World");
    try testing.expect(std.mem.eql(u8, mutable_str.slice(), "Hello World"));

    // 测试位集
    var bits = try BitSet.init(allocator, 100);
    defer bits.deinit();

    try bits.set(42);
    try testing.expect(try bits.isSet(42));
    try testing.expect(!try bits.isSet(43));
}
