pub fn GET(ctx: zx.RouteContext) !void {
    const writer = if (ctx.response.writer()) |w| w else return error.WriterNotFound;
    try zx.util.zxon.serialize(.{
        .users = users.users,
        .events = events.events,
    }, writer, .{});
    ctx.response.setContentType(.@"application/json");
}

const users = @import("../../pages/users.zon");
const events = @import("../../pages/events.zon");

const zx = @import("zx");
