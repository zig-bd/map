const std = @import("std");
const types = @import("types");
const zx = @import("zx");

const UsersFile = struct { users: []const types.User };
const EventsFile = struct { events: []const types.Event };
const MirrorsFile = struct { mirrors: []const types.Mirror };

pub fn GET(ctx: zx.RouteContext) !void {
    const writer = if (ctx.response.writer()) |w| w else return error.WriterNotFound;

    const users = try loadZon(UsersFile, ctx, "app/data/users.zon");
    const events = try loadZon(EventsFile, ctx, "app/data/events.zon");
    const mirrors = try loadZon(MirrorsFile, ctx, "app/data/mirrors.zon");

    try zx.util.zxon.serialize(.{
        .users = users.users,
        .events = events.events,
        .mirrors = mirrors.mirrors,
    }, writer, .{});
    ctx.response.setContentType(.@"application/json");
}

fn loadZon(comptime T: type, ctx: zx.RouteContext, path: []const u8) !T {
    const raw = try std.Io.Dir.cwd().readFileAlloc(ctx.io, path, ctx.arena, .limited(64 * 1024 * 1024));
    const source = try ctx.arena.dupeSentinel(u8, raw, 0);
    var diagnostics: std.zon.parse.Diagnostics = undefined;
    return std.zon.parse.fromSlice(T, .{
        .gpa = ctx.arena,
        .arena = ctx.arena,
        .source = source,
        .diagnostics = &diagnostics,
        .ignore_unknown_fields = true,
    });
}
