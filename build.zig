const std = @import("std");
const ziex = @import("ziex");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const app_exe = b.addExecutable(.{
        .name = "ziguanas",
        .root_module = b.createModule(.{
            .root_source_file = b.path("app/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{},
        }),
    });

    _ = try ziex.init(b, app_exe, .{
        .app = .{
            .client = .{
                .bindings = .{
                    .from_source = true,
                },
            },
        },
    });

    const branding = b.dependency("zig_branding", .{});
    const install_branding = b.addInstallDirectory(.{
        .source_dir = branding.path("."),
        .install_dir = .prefix,
        .install_subdir = "static/assets/branding",
        .include_extensions = &.{ "svg", "png", "webp", "gif" },
    });
    install_branding.step.name = "install branding";
    b.getInstallStep().dependOn(&install_branding.step);

    const source_exe = b.addExecutable(.{
        .name = "ziguanas_source",
        .root_module = b.createModule(.{
            .root_source_file = b.path("source/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const source_step = b.step("source", "Fetch external map sources into app/pages/map/users.zon");
    const source_run = b.addRunArtifact(source_exe);
    source_run.has_side_effects = true;
    source_run.setCwd(b.path("."));
    source_run.addPassthruArgs();
    source_step.dependOn(&source_run.step);
}
