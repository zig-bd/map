pub fn GET(ctx: zx.RouteContext) !void {
    const writer = if (ctx.response.writer()) |w| w else return error.WriterNotFound;
    try zx.util.zxon.serialize(places, writer, .{});
    ctx.response.setContentType(.@"application/json");
}

const places = @import("places.zon");

const zx = @import("zx");
