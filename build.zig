const std = @import("std");

/// Garlic Java 反编译器 - Zig 实现
/// 构建配置文件
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 主可执行文件
    const exe = b.addExecutable(.{
        .name = "garlic",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // 添加 C 库依赖
    exe.linkLibC();

    // 安装可执行文件
    b.installArtifact(exe);

    // 运行命令
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "运行 garlic 反编译器");
    run_step.dependOn(&run_cmd.step);

    // 测试
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // 为测试添加模块路径
    unit_tests.root_module.addImport("jvm", b.createModule(.{
        .root_source_file = b.path("src/jvm/jvm.zig"),
    }));
    unit_tests.root_module.addImport("parser", b.createModule(.{
        .root_source_file = b.path("src/parser/bytecode.zig"),
    }));

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "运行单元测试");
    test_step.dependOn(&run_unit_tests.step);

    // 反编译器测试
    const decompiler_tests = b.addTest(.{
        .root_source_file = b.path("src/decompiler/decompiler.zig"),
        .target = target,
        .optimize = optimize,
    });

    // 为反编译器测试添加模块路径
    decompiler_tests.root_module.addImport("jvm", b.createModule(.{
        .root_source_file = b.path("src/jvm/jvm.zig"),
    }));
    decompiler_tests.root_module.addImport("parser", b.createModule(.{
        .root_source_file = b.path("src/parser/bytecode.zig"),
    }));

    const run_decompiler_tests = b.addRunArtifact(decompiler_tests);
    const decompiler_test_step = b.step("test-decompiler", "运行反编译器测试");
    decompiler_test_step.dependOn(&run_decompiler_tests.step);

    // 基准测试
    const bench_tests = b.addTest(.{
        .root_source_file = b.path("src/bench.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });

    const run_bench_tests = b.addRunArtifact(bench_tests);
    const bench_step = b.step("bench", "运行性能基准测试");
    bench_step.dependOn(&run_bench_tests.step);
}
