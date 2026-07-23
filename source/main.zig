const std = @import("std");
const zig_community = @import("zig_community.zig");
const zig_day = @import("zig_day.zig");

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var args = try init.minimal.args.iterateAllocator(allocator);
    defer args.deinit();
    _ = args.next(); // program name

    const source_name = args.next() orelse {
        std.log.err("usage: zig build source -- <name>", .{});
        std.log.err("available: zig_community, zig_day", .{});
        return error.MissingSourceName;
    };

    if (std.mem.eql(u8, source_name, "zig_community")) {
        const out_path = args.next() orelse "app/pages/users.zon";
        try zig_community.run(init.io, allocator, out_path);
        return;
    }

    if (std.mem.eql(u8, source_name, "zig_day")) {
        const out_path = args.next() orelse "app/pages/events.zon";
        try zig_day.run(init.io, allocator, out_path);
        return;
    }

    std.log.err("unknown source: {s}", .{source_name});
    return error.UnknownSource;
}
