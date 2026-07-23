pub fn GET(ctx: zx.RouteContext) !void {
    const writer = if (ctx.response.writer()) |w| w else return error.WriterNotFound;
    try zx.util.zxon.serialize(.{
        .users = users.users,
        .events = events.events,
        .mirrors = mirrors.mirrors,
    }, writer, .{});
    ctx.response.setContentType(.@"application/json");
}

const users = @import("../../data/users.zon");
const events = @import("../../data/events.zon");
const mirrors = @import("../../data/mirrors.zon");

const zx = @import("zx");
