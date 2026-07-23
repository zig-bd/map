const std = @import("std");
const types = @import("types");

const mirrors_url = "https://ziglang.org/download/community-mirrors.txt";
const geo_url_fmt = "http://ip-api.com/json/{s}?fields=status,message,lat,lon,city,country";

const Link = types.Link;
const Place = types.Place;
const Mirror = types.Mirror;

const MirrorsFile = struct {
    mirrors: []const Mirror,
};

const GeoJson = struct {
    status: []const u8,
    message: ?[]const u8 = null,
    lat: ?f64 = null,
    lon: ?f64 = null,
    city: ?[]const u8 = null,
    country: ?[]const u8 = null,
};

pub fn run(io: std.Io, allocator: std.mem.Allocator, out_path: []const u8) !void {
    std.log.info("fetching {s}", .{mirrors_url});
    const body = try httpGet(io, allocator, mirrors_url, "text/plain");
    defer allocator.free(body);

    var mirrors: std.ArrayList(Mirror) = .empty;
    defer mirrors.deinit(allocator);

    var lines = std.mem.splitScalar(u8, body, '\n');
    while (lines.next()) |raw_line| {
        const line = trimAscii(raw_line);
        if (line.len == 0 or line[0] == '#') continue;

        const host = hostFromUrl(line) orelse {
            std.log.warn("skip invalid mirror url: {s}", .{line});
            continue;
        };

        const geo_url = try std.fmt.allocPrint(allocator, geo_url_fmt, .{host});
        defer allocator.free(geo_url);

        std.log.info("geolocating {s}", .{host});
        const geo_raw = httpGet(io, allocator, geo_url, "application/json") catch |err| {
            std.log.warn("skip {s}: {s}", .{ host, @errorName(err) });
            continue;
        };
        defer allocator.free(geo_raw);

        const parsed = std.json.parseFromSlice(GeoJson, allocator, geo_raw, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        }) catch |err| {
            std.log.warn("skip {s}: {s}", .{ host, @errorName(err) });
            continue;
        };
        defer parsed.deinit();

        if (!std.mem.eql(u8, parsed.value.status, "success")) {
            std.log.warn("skip {s}: {s}", .{ host, parsed.value.message orelse "geo failed" });
            continue;
        }
        const lat = parsed.value.lat orelse continue;
        const lng = parsed.value.lon orelse continue;

        const places = try allocator.alloc(Place, 1);
        places[0] = .{
            .lat = lat,
            .lng = lng,
            .city = try allocator.dupe(u8, parsed.value.city orelse ""),
        };

        const links = try allocator.alloc(Link, 1);
        links[0] = .{
            .label = "Mirror",
            .href = try allocator.dupe(u8, line),
        };

        try mirrors.append(allocator, .{
            .name = try allocator.dupe(u8, host),
            .places = places,
            .links = links,
        });
    }

    std.mem.sort(Mirror, mirrors.items, {}, struct {
        fn less(_: void, a: Mirror, b: Mirror) bool {
            return std.ascii.lessThanIgnoreCase(a.name, b.name);
        }
    }.less);

    var aw = std.Io.Writer.Allocating.init(allocator);
    defer aw.deinit();
    try std.zon.stringify.serialize(
        MirrorsFile{ .mirrors = mirrors.items },
        .{
            .whitespace = true,
            .emit_default_optional_fields = false,
        },
        &aw.writer,
    );
    try aw.writer.writeByte('\n');

    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = out_path, .data = aw.written() });
    std.log.info("wrote {d} mirrors to {s}", .{ mirrors.items.len, out_path });
}

fn hostFromUrl(url: []const u8) ?[]const u8 {
    var rest = url;
    if (std.mem.startsWith(u8, rest, "https://")) {
        rest = rest["https://".len..];
    } else if (std.mem.startsWith(u8, rest, "http://")) {
        rest = rest["http://".len..];
    } else return null;

    const end = std.mem.indexOfAny(u8, rest, "/:") orelse rest.len;
    if (end == 0) return null;
    return rest[0..end];
}

fn trimAscii(s: []const u8) []const u8 {
    return std.mem.trim(u8, s, " \t\r\n");
}

fn httpGet(io: std.Io, allocator: std.mem.Allocator, url: []const u8, accept: []const u8) ![]u8 {
    var client: std.http.Client = .{ .allocator = allocator, .io = io };
    defer client.deinit();

    var aw = std.Io.Writer.Allocating.init(allocator);
    defer aw.deinit();

    const result = client.fetch(.{
        .location = .{ .url = url },
        .method = .GET,
        .redirect_behavior = @enumFromInt(5),
        .response_writer = &aw.writer,
        .extra_headers = &.{
            .{ .name = "user-agent", .value = "ziex-bench-source" },
            .{ .name = "accept", .value = accept },
        },
    }) catch return error.NetworkError;

    if (result.status != .ok) return error.NetworkError;
    return try allocator.dupe(u8, aw.written());
}
