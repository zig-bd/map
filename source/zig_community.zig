const std = @import("std");
const types = @import("types");

const tarball_url = "https://codeload.github.com/zig-community/user-map/tar.gz/refs/heads/master";

const PersonJson = struct {
    nick: []const u8,
    coordinates: [2]f64,
    links: ?std.json.Value = null,
};

const Link = types.Link;
const Place = types.Place;
const User = types.User;

const UsersFile = struct {
    users: []const User,
};

pub fn run(io: std.Io, allocator: std.mem.Allocator, out_path: []const u8) !void {
    std.log.info("fetching {s}", .{tarball_url});
    const gz = try httpGet(io, allocator, tarball_url);
    defer allocator.free(gz);

    const cache_dir_path = ".zig-cache/ziex-source-zc";
    std.Io.Dir.cwd().deleteTree(io, cache_dir_path) catch {};
    try std.Io.Dir.cwd().createDirPath(io, cache_dir_path);

    var dest = try std.Io.Dir.cwd().openDir(io, cache_dir_path, .{});
    defer dest.close(io);

    var gz_reader: std.Io.Reader = .fixed(gz);
    var decompress_buf: [std.compress.flate.max_window_len]u8 = undefined;
    var decompress: std.compress.flate.Decompress = .init(&gz_reader, .gzip, &decompress_buf);
    try std.tar.extract(io, dest, &decompress.reader, .{
        .strip_components = 1,
        .mode_mode = .executable_bit_only,
    });

    var people_dir = try dest.openDir(io, "people", .{ .iterate = true });
    defer people_dir.close(io);

    var users: std.ArrayList(User) = .empty;
    defer users.deinit(allocator);

    var walker = try people_dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.basename, ".json")) continue;

        const file_raw = try entry.dir.readFileAlloc(io, entry.basename, allocator, .limited(256 * 1024));
        defer allocator.free(file_raw);

        const parsed = std.json.parseFromSlice(PersonJson, allocator, file_raw, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        }) catch |err| {
            std.log.warn("skip {s}: {s}", .{ entry.basename, @errorName(err) });
            continue;
        };
        defer parsed.deinit();

        const places = try allocator.alloc(Place, 1);
        places[0] = .{
            .lat = parsed.value.coordinates[0],
            .lng = parsed.value.coordinates[1],
        };

        try users.append(allocator, .{
            .username = try allocator.dupe(u8, parsed.value.nick),
            .places = places,
            .links = try parseLinks(allocator, parsed.value.links),
        });
    }

    std.mem.sort(User, users.items, {}, struct {
        fn less(_: void, a: User, b: User) bool {
            return std.ascii.lessThanIgnoreCase(a.username, b.username);
        }
    }.less);

    var aw = std.Io.Writer.Allocating.init(allocator);
    defer aw.deinit();
    try std.zon.stringify.serialize(
        UsersFile{ .users = users.items },
        .{
            .whitespace = true,
            .emit_default_optional_fields = false,
        },
        &aw.writer,
    );
    try aw.writer.writeByte('\n');

    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = out_path, .data = aw.written() });
    std.log.info("wrote {d} users to {s}", .{ users.items.len, out_path });
}

fn httpGet(io: std.Io, allocator: std.mem.Allocator, url: []const u8) ![]u8 {
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
            .{ .name = "accept", .value = "application/octet-stream" },
        },
    }) catch return error.NetworkError;

    if (result.status != .ok) return error.NetworkError;
    return try allocator.dupe(u8, aw.written());
}

fn parseLinks(allocator: std.mem.Allocator, value: ?std.json.Value) ![]const Link {
    const v = value orelse return &.{};
    if (v != .object) return &.{};

    var list: std.ArrayList(Link) = .empty;
    errdefer list.deinit(allocator);

    var it = v.object.iterator();
    while (it.next()) |entry| {
        if (entry.value_ptr.* != .string) continue;
        try list.append(allocator, .{
            .label = try allocator.dupe(u8, entry.key_ptr.*),
            .href = try allocator.dupe(u8, entry.value_ptr.*.string),
        });
    }

    std.mem.sort(Link, list.items, {}, struct {
        fn less(_: void, a: Link, b: Link) bool {
            return std.ascii.lessThanIgnoreCase(a.label, b.label);
        }
    }.less);

    return try list.toOwnedSlice(allocator);
}
