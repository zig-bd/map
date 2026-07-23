const std = @import("std");

const page_url = "https://zig.day/";

const Link = struct {
    label: []const u8,
    href: []const u8,
};

const Place = struct {
    city: []const u8 = "",
    lat: f64,
    lng: f64,
};

const Event = struct {
    name: []const u8,
    places: []const Place,
    links: []const Link = &.{},
};

const EventsFile = struct {
    events: []const Event,
};

pub fn run(io: std.Io, allocator: std.mem.Allocator, out_path: []const u8) !void {
    std.log.info("fetching {s}", .{page_url});
    const html = try httpGet(io, allocator, page_url);
    defer allocator.free(html);

    var events: std.ArrayList(Event) = .empty;
    defer events.deinit(allocator);

    var rest = html;
    while (findAnchor(rest)) |anchor| {
        defer rest = rest[anchor.end..];

        const lat_s = attrValue(anchor.tag, "data-longitude") orelse continue;
        const lng_s = attrValue(anchor.tag, "data-latitude") orelse continue;
        const href = attrValue(anchor.tag, "href") orelse continue;

        const lat = std.fmt.parseFloat(f64, lat_s) catch continue;
        const lng = std.fmt.parseFloat(f64, lng_s) catch continue;

        const name = try decodeEntities(allocator, trimAscii(anchor.body));
        if (name.len == 0) continue;

        const places = try allocator.alloc(Place, 1);
        places[0] = .{ .lat = lat, .lng = lng };

        const abs_href = try absUrl(allocator, href);
        const links = try allocator.alloc(Link, 1);
        links[0] = .{
            .label = "Zig Day",
            .href = abs_href,
        };

        try events.append(allocator, .{
            .name = name,
            .places = places,
            .links = links,
        });
    }

    std.mem.sort(Event, events.items, {}, struct {
        fn less(_: void, a: Event, b: Event) bool {
            return std.ascii.lessThanIgnoreCase(a.name, b.name);
        }
    }.less);

    var aw = std.Io.Writer.Allocating.init(allocator);
    defer aw.deinit();
    try std.zon.stringify.serialize(
        EventsFile{ .events = events.items },
        .{
            .whitespace = true,
            .emit_default_optional_fields = false,
        },
        &aw.writer,
    );
    try aw.writer.writeByte('\n');

    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = out_path, .data = aw.written() });
    std.log.info("wrote {d} events to {s}", .{ events.items.len, out_path });
}

const Anchor = struct {
    tag: []const u8,
    body: []const u8,
    end: usize,
};

fn findAnchor(html: []const u8) ?Anchor {
    const open = std.mem.indexOf(u8, html, "<a ") orelse return null;
    const tag_end = std.mem.indexOfPos(u8, html, open, ">") orelse return null;
    const close = std.mem.indexOfPos(u8, html, tag_end + 1, "</a>") orelse return null;
    return .{
        .tag = html[open .. tag_end + 1],
        .body = html[tag_end + 1 .. close],
        .end = close + "</a>".len,
    };
}

fn attrValue(tag: []const u8, name: []const u8) ?[]const u8 {
    var buf: [64]u8 = undefined;
    const key = std.fmt.bufPrint(&buf, "{s}=\"", .{name}) catch return null;
    const start = std.mem.indexOf(u8, tag, key) orelse return null;
    const value_start = start + key.len;
    const value_end = std.mem.indexOfPos(u8, tag, value_start, "\"") orelse return null;
    return tag[value_start..value_end];
}

fn absUrl(allocator: std.mem.Allocator, href: []const u8) ![]const u8 {
    if (std.mem.startsWith(u8, href, "http://") or std.mem.startsWith(u8, href, "https://")) {
        return try allocator.dupe(u8, href);
    }
    if (std.mem.startsWith(u8, href, "/")) {
        return try std.fmt.allocPrint(allocator, "https://zig.day{s}", .{href});
    }
    return try std.fmt.allocPrint(allocator, "https://zig.day/{s}", .{href});
}

fn trimAscii(s: []const u8) []const u8 {
    return std.mem.trim(u8, s, " \t\r\n");
}

fn decodeEntities(allocator: std.mem.Allocator, raw: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    var i: usize = 0;
    while (i < raw.len) {
        if (raw[i] == '&') {
            if (std.mem.startsWith(u8, raw[i..], "&apos;")) {
                try out.append(allocator, '\'');
                i += "&apos;".len;
                continue;
            }
            if (std.mem.startsWith(u8, raw[i..], "&amp;")) {
                try out.append(allocator, '&');
                i += "&amp;".len;
                continue;
            }
            if (std.mem.startsWith(u8, raw[i..], "&quot;")) {
                try out.append(allocator, '"');
                i += "&quot;".len;
                continue;
            }
            if (std.mem.startsWith(u8, raw[i..], "&lt;")) {
                try out.append(allocator, '<');
                i += "&lt;".len;
                continue;
            }
            if (std.mem.startsWith(u8, raw[i..], "&gt;")) {
                try out.append(allocator, '>');
                i += "&gt;".len;
                continue;
            }
        }
        try out.append(allocator, raw[i]);
        i += 1;
    }
    return try out.toOwnedSlice(allocator);
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
            .{ .name = "accept", .value = "text/html" },
        },
    }) catch return error.NetworkError;

    if (result.status != .ok) return error.NetworkError;
    return try allocator.dupe(u8, aw.written());
}
