const std = @import("std");
const zx = @import("zx");

pub const users: Users = @import("users.zon");

pub const TILE: f64 = 256;
pub const MIN_Z: f64 = 2.0;
pub const MAX_Z: f64 = 18.0;
pub const ZOOM_STEP_BUTTON: f64 = 0.55;
pub const ZOOM_WHEEL_SENS: f64 = 0.0020;
pub const HIT_PX: f64 = 18;
pub const CLICK_SLOP_PX: i32 = 6;

pub const Link = struct {
    label: []const u8,
    href: []const u8,
};

pub const Place = struct {
    city: []const u8 = "",
    lat: f64,
    lng: f64,
};

pub const Mascot = enum { zero, carmen, ziggy };

pub const Avatar = struct {
    mascot: Mascot,
};

pub const User = struct {
    username: []const u8,
    avatar: ?Avatar = null,
    places: []const Place,
    links: []const Link = &.{},
};

pub const Users = struct {
    users: []const User,
};

pub const Pin = struct {
    user_index: usize,
    username: []const u8,
    city: []const u8,
    lat: f64,
    lng: f64,
    links: []const Link,
    mascot: ?Mascot = null,
};

pub const pins: []const Pin = blk: {
    var n: usize = 0;
    for (users.users) |u| n += u.places.len;
    var arr: [n]Pin = undefined;
    var i: usize = 0;
    for (users.users, 0..) |u, ui| {
        for (u.places) |place| {
            arr[i] = .{
                .user_index = ui,
                .username = u.username,
                .city = place.city,
                .lat = place.lat,
                .lng = place.lng,
                .links = u.links,
                .mascot = if (u.avatar) |a| a.mascot else null,
            };
            i += 1;
        }
    }
    const frozen = arr;
    break :blk &frozen;
};

pub const Camera = struct {
    x: f64,
    y: f64,
    z: f64,
};

pub const Drag = struct {
    active: bool = false,
    moved: bool = false,
    last_x: i32 = 0,
    last_y: i32 = 0,
    start_x: i32 = 0,
    start_y: i32 = 0,
    pointer_id: i32 = -1,
};

pub const Tip = struct {
    selected: ?usize = null,
    hovered: ?usize = null,
};

pub const Search = struct {
    open: bool = false,
    query: [64]u8 = undefined,
    len: usize = 0,

    pub fn text(self: *const Search) []const u8 {
        return self.query[0..self.len];
    }
};

pub const TileView = struct {
    z: u8,
    x: u32,
    y: u32,
    left: f64,
    top: f64,
    size: f64,
};

pub const DockEntry = struct {
    user_index: usize,
    username: []const u8,
    first_city: []const u8,
    extra_places: usize = 0,
    place_label: []const u8 = "",
};

const FLY_Z: f64 = 7.0;
const SEARCH_RESULT_CAP: usize = 12;

// TODO: use one single state struct with all the states as fields
fn skipStates(e: *zx.client.Event.Stateful) void {
    _ = e.state(Camera);
    _ = e.state(Drag);
    _ = e.state(Tip);
    _ = e.state(Search);
}

pub fn pinClass(tip: Tip, i: usize, pin: Pin) []const u8 {
    const mascot = pin.mascot != null;
    if (tip.selected == i) return if (mascot) "map-pin has-mascot is-active" else "map-pin is-active";
    if (tip.hovered == i) return if (mascot) "map-pin has-mascot is-hot" else "map-pin is-hot";
    return if (mascot) "map-pin has-mascot" else "map-pin";
}

pub fn collectDockEntries(allocator: zx.Allocator, out: *std.ArrayListUnmanaged(DockEntry), visible: []const Pin) void {
    for (visible) |pin| {
        for (out.items) |*entry| {
            if (entry.user_index == pin.user_index) {
                entry.extra_places += 1;
                entry.place_label = fmtDockPlace(allocator, entry.first_city, entry.extra_places) catch entry.first_city;
                break;
            }
        } else {
            out.append(allocator, .{
                .user_index = pin.user_index,
                .username = pin.username,
                .first_city = pin.city,
                .extra_places = 0,
                .place_label = pin.city,
            }) catch {};
        }
    }
}

fn fmtDockPlace(allocator: zx.Allocator, first_city: []const u8, extra: usize) ![]const u8 {
    if (extra == 0) return first_city;
    if (first_city.len == 0) return try std.fmt.allocPrint(allocator, "+{d}", .{extra});
    return try std.fmt.allocPrint(allocator, "{s} + {d}", .{ first_city, extra });
}

fn worldSize(z: f64) f64 {
    return TILE * std.math.exp2(z);
}

fn project(lat: f64, lng: f64, z: f64) struct { x: f64, y: f64 } {
    const lat_c = std.math.clamp(lat, -85.05112878, 85.05112878);
    const sin_y = @sin(lat_c * std.math.pi / 180.0);
    const y = 0.5 - @log((1.0 + sin_y) / (1.0 - sin_y)) / (4.0 * std.math.pi);
    const w = worldSize(z);
    return .{
        .x = (lng + 180.0) / 360.0 * w,
        .y = y * w,
    };
}

fn effectiveMinZoom(el_w: f64, el_h: f64) f64 {
    var min_z = MIN_Z;
    if (el_h > 0) min_z = @max(min_z, std.math.log2(el_h / TILE));
    if (el_w > 0) min_z = @max(min_z, std.math.log2(el_w / TILE));
    return @min(min_z, MAX_Z);
}

pub fn initialCamera(el_w: f64, el_h: f64) Camera {
    const z = @max(effectiveMinZoom(el_w, el_h), MIN_Z + 0.35);
    const w = worldSize(z);
    return clampCamera(.{
        .x = (w - el_w) * 0.5,
        .y = (w - el_h) * 0.42,
        .z = z,
    }, el_w, el_h);
}

fn clampAxis(value: f64, world: f64, view: f64) f64 {
    if (world <= view) return (world - view) * 0.5;
    return std.math.clamp(value, 0.0, world - view);
}

pub fn clampCamera(cam: Camera, el_w: f64, el_h: f64) Camera {
    const min_z = effectiveMinZoom(el_w, el_h);
    var next = Camera{
        .x = cam.x,
        .y = cam.y,
        .z = std.math.clamp(cam.z, min_z, MAX_Z),
    };
    const w = worldSize(next.z);
    next.x = clampAxis(next.x, w, el_w);
    next.y = clampAxis(next.y, w, el_h);
    return next;
}

pub fn zoomTo(cam: Camera, new_z: f64, focus_x: f64, focus_y: f64, el_w: f64, el_h: f64) Camera {
    const min_z = effectiveMinZoom(el_w, el_h);
    const z = std.math.clamp(new_z, min_z, MAX_Z);
    if (@abs(z - cam.z) < 1e-9) return clampCamera(cam, el_w, el_h);
    const scale = std.math.exp2(z - cam.z);
    return clampCamera(.{
        .x = (cam.x + focus_x) * scale - focus_x,
        .y = (cam.y + focus_y) * scale - focus_y,
        .z = z,
    }, el_w, el_h);
}

pub fn collectTilesAt(
    allocator: zx.Allocator,
    out: *std.ArrayListUnmanaged(TileView),
    cam: Camera,
    el_w: f64,
    el_h: f64,
    z_tile: u8,
) void {
    const tile_span = TILE * std.math.exp2(cam.z - @as(f64, @floatFromInt(z_tile)));
    const n: i32 = @intCast(@as(u32, 1) << @intCast(z_tile));

    const x0: i32 = @intFromFloat(@floor(cam.x / tile_span));
    const y0: i32 = @intFromFloat(@floor(cam.y / tile_span));
    const x1: i32 = @intFromFloat(@floor((cam.x + el_w) / tile_span));
    const y1: i32 = @intFromFloat(@floor((cam.y + el_h) / tile_span));

    var ty = y0;
    while (ty <= y1) : (ty += 1) {
        if (ty < 0 or ty >= n) continue;
        var tx = x0;
        while (tx <= x1) : (tx += 1) {
            if (tx < 0 or tx >= n) continue;
            out.append(allocator, .{
                .z = z_tile,
                .x = @intCast(tx),
                .y = @intCast(ty),
                .left = @as(f64, @floatFromInt(tx)) * tile_span - cam.x,
                .top = @as(f64, @floatFromInt(ty)) * tile_span - cam.y,
                .size = tile_span,
            }) catch {};
        }
    }
}

pub fn pinInView(pin: Pin, cam: Camera, el_w: f64, el_h: f64) bool {
    const p = screenPos(pin, cam);
    return p.x >= -HIT_PX and p.x <= el_w + HIT_PX and p.y >= -HIT_PX and p.y <= el_h + HIT_PX;
}

pub fn screenPos(pin: Pin, cam: Camera) struct { x: f64, y: f64 } {
    const p = project(pin.lat, pin.lng, cam.z);
    return .{ .x = p.x - cam.x, .y = p.y - cam.y };
}

fn hitPinIndex(sx: f64, sy: f64, cam: Camera) ?usize {
    var best_i: ?usize = null;
    var best_d: f64 = HIT_PX * HIT_PX;
    for (pins, 0..) |pin, i| {
        const p = screenPos(pin, cam);
        const dx = p.x - sx;
        const dy = p.y - sy;
        const d = dx * dx + dy * dy;
        if (d <= best_d) {
            best_d = d;
            best_i = i;
        }
    }
    return best_i;
}

pub fn stageSize() struct { w: f64, h: f64 } {
    if (!zx.platform.isClient()) return .{ .w = 1280, .h = 800 };
    const document = zx.client.Document.init(zx.allocator);
    const el = document.getElementById("map-stage") catch return .{ .w = 1280, .h = 800 };
    defer el.deinit();
    const w = el.getProperty(f64, "clientWidth") catch 1280;
    const h = el.getProperty(f64, "clientHeight") catch 800;
    if (w <= 0 or h <= 0) return .{ .w = 1280, .h = 800 };
    return .{ .w = w, .h = h };
}

fn pointerFocus(client_x: i32, client_y: i32, el_w: f64, el_h: f64) struct { x: f64, y: f64 } {
    if (!zx.platform.isClient()) return .{ .x = el_w * 0.5, .y = el_h * 0.5 };
    const document = zx.client.Document.init(zx.allocator);
    const el = document.getElementById("map-stage") catch return .{ .x = el_w * 0.5, .y = el_h * 0.5 };
    defer el.deinit();
    const rect = el.ref.call(@import("js").Object, "getBoundingClientRect", .{}) catch {
        return .{ .x = el_w * 0.5, .y = el_h * 0.5 };
    };
    defer rect.deinit();
    const left = rect.get(f64, "left") catch 0;
    const top = rect.get(f64, "top") catch 0;
    return .{
        .x = std.math.clamp(@as(f64, @floatFromInt(client_x)) - left, 0, el_w),
        .y = std.math.clamp(@as(f64, @floatFromInt(client_y)) - top, 0, el_h),
    };
}

fn capturePointer(pointer_id: i32) void {
    if (!zx.platform.isClient()) return;
    const document = zx.client.Document.init(zx.allocator);
    const el = document.getElementById("map-stage") catch return;
    defer el.deinit();
    el.ref.call(void, "setPointerCapture", .{pointer_id}) catch {};
}

fn releasePointer(pointer_id: i32) void {
    if (!zx.platform.isClient() or pointer_id < 0) return;
    const document = zx.client.Document.init(zx.allocator);
    const el = document.getElementById("map-stage") catch return;
    defer el.deinit();
    el.ref.call(void, "releasePointerCapture", .{pointer_id}) catch {};
}

fn firstPinForUser(user_index: usize) ?usize {
    for (pins, 0..) |pin, i| {
        if (pin.user_index == user_index) return i;
    }
    return null;
}

fn focusUser(
    camera: anytype,
    tip: anytype,
    user_index: usize,
    el_w: f64,
    el_h: f64,
) void {
    const pin_i = firstPinForUser(user_index) orelse return;
    const pin = pins[pin_i];
    const p = project(pin.lat, pin.lng, FLY_Z);
    camera.set(clampCamera(.{
        .x = p.x - el_w * 0.5,
        .y = p.y - el_h * 0.45,
        .z = FLY_Z,
    }, el_w, el_h));
    tip.set(.{ .selected = pin_i, .hovered = pin_i });
}

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0 or needle.len > haystack.len) return false;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        var ok = true;
        for (needle, 0..) |nc, j| {
            if (std.ascii.toLower(haystack[i + j]) != std.ascii.toLower(nc)) {
                ok = false;
                break;
            }
        }
        if (ok) return true;
    }
    return false;
}

pub fn collectSearchResults(allocator: zx.Allocator, query: []const u8, out: *std.ArrayListUnmanaged(usize)) void {
    if (query.len == 0) return;
    for (users.users, 0..) |user, ui| {
        if (!containsIgnoreCase(user.username, query)) continue;
        out.append(allocator, ui) catch {};
        if (out.items.len >= SEARCH_RESULT_CAP) break;
    }
}

pub fn onWheel(e: *zx.client.Event.Stateful) void {
    e.preventDefault();
    if (!zx.platform.isClient()) return;
    const camera = e.state(Camera);
    _ = e.state(Drag);
    _ = e.state(Tip);
    _ = e.state(Search);

    const we = e.as(zx.client.events.WheelEvent, zx.allocator);
    const size = stageSize();
    const cam = clampCamera(camera.get(), size.w, size.h);
    const focus = pointerFocus(we.client_x, we.client_y, size.w, size.h);

    var delta = we.delta_y;
    if (we.delta_mode == 1) delta *= 16;
    if (we.delta_mode == 2) delta *= size.h;
    delta = std.math.clamp(delta, -100.0, 100.0);

    camera.set(zoomTo(cam, cam.z - delta * ZOOM_WHEEL_SENS, focus.x, focus.y, size.w, size.h));
}

pub fn onPointerDown(e: *zx.client.Event.Stateful) void {
    e.preventDefault();
    if (!zx.platform.isClient()) return;
    _ = e.state(Camera);
    const drag = e.state(Drag);
    _ = e.state(Tip);
    _ = e.state(Search);
    const pe = e.as(zx.client.events.PointerEvent, zx.allocator);
    if (pe.button != 0) return;
    capturePointer(pe.pointer_id);
    drag.set(.{
        .active = true,
        .moved = false,
        .last_x = pe.client_x,
        .last_y = pe.client_y,
        .start_x = pe.client_x,
        .start_y = pe.client_y,
        .pointer_id = pe.pointer_id,
    });
}

pub fn onPointerMove(e: *zx.client.Event.Stateful) void {
    if (!zx.platform.isClient()) return;
    const camera = e.state(Camera);
    const drag = e.state(Drag);
    const tip = e.state(Tip);
    _ = e.state(Search);
    var d = drag.get();
    const pe = e.as(zx.client.events.PointerEvent, zx.allocator);
    const size = stageSize();
    var cam = clampCamera(camera.get(), size.w, size.h);

    if (d.active) {
        if ((pe.buttons & 1) == 0) {
            releasePointer(d.pointer_id);
            d.active = false;
            d.pointer_id = -1;
            drag.set(d);
            return;
        }
        const adx = @abs(pe.client_x - d.start_x);
        const ady = @abs(pe.client_y - d.start_y);
        if (adx > CLICK_SLOP_PX or ady > CLICK_SLOP_PX) d.moved = true;

        if (d.moved) {
            e.preventDefault();
            cam.x -= @as(f64, @floatFromInt(pe.client_x - d.last_x));
            cam.y -= @as(f64, @floatFromInt(pe.client_y - d.last_y));
            camera.set(clampCamera(cam, size.w, size.h));
            var t = tip.get();
            t.hovered = null;
            tip.set(t);
        }
        d.last_x = pe.client_x;
        d.last_y = pe.client_y;
        drag.set(d);
        return;
    }

    const focus = pointerFocus(pe.client_x, pe.client_y, size.w, size.h);
    var t = tip.get();
    t.hovered = hitPinIndex(focus.x, focus.y, cam);
    tip.set(t);
}

pub fn onPointerUp(e: *zx.client.Event.Stateful) void {
    if (!zx.platform.isClient()) return;
    const camera = e.state(Camera);
    const drag = e.state(Drag);
    const tip = e.state(Tip);
    _ = e.state(Search);
    const d = drag.get();
    if (!d.active) return;

    const pe = e.as(zx.client.events.PointerEvent, zx.allocator);
    releasePointer(d.pointer_id);

    if (!d.moved) {
        const size = stageSize();
        const cam = clampCamera(camera.get(), size.w, size.h);
        const focus = pointerFocus(pe.client_x, pe.client_y, size.w, size.h);
        var t = tip.get();
        t.selected = hitPinIndex(focus.x, focus.y, cam);
        t.hovered = t.selected;
        tip.set(t);
    }
    drag.set(.{});
}

pub fn onPointerLeave(e: *zx.client.Event.Stateful) void {
    if (!zx.platform.isClient()) return;
    _ = e.state(Camera);
    _ = e.state(Drag);
    const tip = e.state(Tip);
    _ = e.state(Search);
    var t = tip.get();
    t.hovered = null;
    tip.set(t);
}

pub fn onControlsPointer(e: *zx.client.Event.Stateful) void {
    e.stopPropagation();
    skipStates(e);
}

pub fn onDockWheel(e: *zx.client.Event.Stateful) void {
    e.stopPropagation();
    skipStates(e);
}

pub fn onTipPointer(e: *zx.client.Event.Stateful) void {
    e.stopPropagation();
    skipStates(e);
}

pub fn onTipClose(e: *zx.client.Event.Stateful) void {
    e.stopPropagation();
    _ = e.state(Camera);
    _ = e.state(Drag);
    e.state(Tip).set(.{});
    _ = e.state(Search);
}

pub fn onZoomIn(e: *zx.client.Event.Stateful) void {
    if (!zx.platform.isClient()) return;
    const camera = e.state(Camera);
    _ = e.state(Drag);
    _ = e.state(Tip);
    _ = e.state(Search);
    const size = stageSize();
    const cam = clampCamera(camera.get(), size.w, size.h);
    camera.set(zoomTo(cam, cam.z + ZOOM_STEP_BUTTON, size.w * 0.5, size.h * 0.5, size.w, size.h));
}

pub fn onZoomOut(e: *zx.client.Event.Stateful) void {
    if (!zx.platform.isClient()) return;
    const camera = e.state(Camera);
    _ = e.state(Drag);
    _ = e.state(Tip);
    _ = e.state(Search);
    const size = stageSize();
    const cam = clampCamera(camera.get(), size.w, size.h);
    camera.set(zoomTo(cam, cam.z - ZOOM_STEP_BUTTON, size.w * 0.5, size.h * 0.5, size.w, size.h));
}

pub fn onReset(e: *zx.client.Event.Stateful) void {
    if (!zx.platform.isClient()) return;
    const size = stageSize();
    e.state(Camera).set(initialCamera(size.w, size.h));
    e.state(Drag).set(.{});
    e.state(Tip).set(.{});
    e.state(Search).set(.{});
}

pub fn onSearchToggle(e: *zx.client.Event.Stateful) void {
    e.stopPropagation();
    if (!zx.platform.isClient()) return;
    _ = e.state(Camera);
    _ = e.state(Drag);
    _ = e.state(Tip);
    const search = e.state(Search);
    var s = search.get();
    s.open = !s.open;
    if (!s.open) s.len = 0;
    search.set(s);
}

pub fn onSearchInput(e: *zx.client.Event.Stateful) void {
    e.stopPropagation();
    if (!zx.platform.isClient()) return;
    _ = e.state(Camera);
    _ = e.state(Drag);
    _ = e.state(Tip);
    const search = e.state(Search);
    const raw = e.value() orelse "";
    var s = search.get();
    const n = @min(raw.len, s.query.len);
    if (n > 0) @memcpy(s.query[0..n], raw[0..n]);
    s.len = n;
    s.open = true;
    search.set(s);
}

pub fn onSearchClear(e: *zx.client.Event.Stateful) void {
    e.stopPropagation();
    if (!zx.platform.isClient()) return;
    _ = e.state(Camera);
    _ = e.state(Drag);
    _ = e.state(Tip);
    e.state(Search).set(.{ .open = true });
}

pub fn onSelectUser(e: *zx.client.Event.Stateful) void {
    e.stopPropagation();
    e.preventDefault();
    if (!zx.platform.isClient()) return;
    const camera = e.state(Camera);
    _ = e.state(Drag);
    const tip = e.state(Tip);
    const search = e.state(Search);

    const raw = e.value() orelse return;
    const user_index = std.fmt.parseInt(usize, raw, 10) catch return;
    const size = stageSize();
    focusUser(camera, tip, user_index, size.w, size.h);
    search.set(.{});
}

pub fn fmtTileSrc(allocator: zx.Allocator, tile: TileView) []const u8 {
    return std.fmt.allocPrint(
        allocator,
        "https://basemaps.cartocdn.com/rastertiles/voyager/{d}/{d}/{d}.png",
        .{ tile.z, tile.x, tile.y },
    ) catch "";
}

pub fn fmtTileStyle(allocator: zx.Allocator, tile: TileView) []const u8 {
    const scale = tile.size / TILE;
    return std.fmt.allocPrint(
        allocator,
        "transform:translate3d({d:.2}px,{d:.2}px,0) scale({d:.5})",
        .{ tile.left, tile.top, scale },
    ) catch "";
}

pub fn fmtPinStyle(allocator: zx.Allocator, pin: Pin, cam: Camera) []const u8 {
    const p = screenPos(pin, cam);
    return std.fmt.allocPrint(allocator, "left:{d:.1}px;top:{d:.1}px", .{ p.x, p.y }) catch "";
}

pub fn fmtMascotSrc(allocator: zx.Allocator, mascot: Mascot) []const u8 {
    return std.fmt.allocPrint(allocator, "/assets/branding/{s}.svg", .{@tagName(mascot)}) catch "";
}

pub fn fmtTipStyle(allocator: zx.Allocator, pin: Pin, cam: Camera) []const u8 {
    const p = screenPos(pin, cam);
    return std.fmt.allocPrint(allocator, "left:{d:.1}px;top:{d:.1}px", .{ p.x, p.y }) catch "";
}

pub fn fmtCount(allocator: zx.Allocator, count: usize) []const u8 {
    return std.fmt.allocPrint(allocator, "{d}", .{count}) catch "0";
}

pub fn fmtIndex(allocator: zx.Allocator, index: usize) []const u8 {
    return std.fmt.allocPrint(allocator, "{d}", .{index}) catch "0";
}

pub fn fmtQueryValue(allocator: zx.Allocator, search: Search) []const u8 {
    return std.fmt.allocPrint(allocator, "{s}", .{search.text()}) catch "";
}
