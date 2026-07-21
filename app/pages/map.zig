const std = @import("std");
const zx = @import("zx");

pub const users: Users = @import("users.zon");

const js = zx.client.js;

pub const TILE: f64 = 256;
pub const MIN_Z: f64 = 2.0;
pub const MAX_Z: f64 = 18.0;
pub const ZOOM_STEP_BUTTON: f64 = 0.55;
pub const ZOOM_WHEEL_SENS: f64 = 0.0020;
pub const ZOOM_TRACKPAD_SENS: f64 = 0.0055;
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
    mx: f64,
    my: f64,
    links: []const Link,
    mascot: ?Mascot = null,
};

pub const pins: []const Pin = blk: {
    @setEvalBranchQuota(100_000);
    var n: usize = 0;
    for (users.users) |u| n += u.places.len;
    var arr: [n]Pin = undefined;
    var i: usize = 0;
    for (users.users, 0..) |u, ui| {
        for (u.places) |place| {
            const m = mercatorNorm(place.lat, place.lng);
            arr[i] = .{
                .user_index = ui,
                .username = u.username,
                .city = place.city,
                .lat = place.lat,
                .lng = place.lng,
                .mx = m.x,
                .my = m.y,
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

/// iOS Safari can expose negative pointer IDs.
const NO_POINTER: i32 = -1;

pub const Drag = struct {
    active: bool = false,
    moved: bool = false,
    second_active: bool = false,
    last_x: i32 = 0,
    last_y: i32 = 0,
    start_x: i32 = 0,
    start_y: i32 = 0,
    pointer_id: i32 = NO_POINTER,
    pointer2_id: i32 = NO_POINTER,
    last2_x: i32 = 0,
    last2_y: i32 = 0,
    last_pinch_dist: f64 = 0,
    world_dx: f64 = 0,
    world_dy: f64 = 0,
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

pub const JoinField = struct {
    bytes: [192]u8 = undefined,
    len: usize = 0,

    pub fn text(self: *const JoinField) []const u8 {
        return self.bytes[0..self.len];
    }

    fn set(self: *JoinField, value: []const u8) void {
        const n = @min(value.len, self.bytes.len);
        if (n > 0) @memcpy(self.bytes[0..n], value[0..n]);
        self.len = n;
    }
};

pub const JoinLink = struct {
    label: JoinField = .{},
    href: JoinField = .{},
};

pub const JoinLocationMode = enum { city, automatic, manual };
pub const JoinError = enum { none, username, location, links, geolocation };
pub const MAX_JOIN_LINKS: usize = 4;

pub const Join = struct {
    open: bool = false,
    username: JoinField = .{},
    location_mode: JoinLocationMode = .city,
    city_index: ?usize = null,
    lat: JoinField = .{},
    lng: JoinField = .{},
    links: [MAX_JOIN_LINKS]JoinLink = @splat(.{}),
    link_count: usize = 1,
    err: JoinError = .none,
};

pub const City = struct {
    name: []const u8,
    country: []const u8,
    lat: f64,
    lng: f64,
};

pub const Places = struct {
    places: []const City,
};

pub const places: Places = @import("places.zon");
pub const cities = places.places;

pub const State = struct {
    camera: Camera,
    drag: Drag = .{},
    tip: Tip = .{},
    search: Search = .{},
    join: Join = .{},
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
const MIN_PINCH_DIST: f64 = 16.0;
const PAN_COMMIT_PX: f64 = 384.0;
const TILE_PAD_PX: f64 = 512.0;

var live_drag: Drag = .{};

const StageCache = struct {
    w: f64 = 1280,
    h: f64 = 800,
    left: f64 = 0,
    top: f64 = 0,
    valid: bool = false,
};

var stage_cache: StageCache = .{};

const CamPreview = struct {
    active: bool = false,
    scheduled: bool = false,
    base: Camera = .{ .x = 0, .y = 0, .z = 0 },
    live: Camera = .{ .x = 0, .y = 0, .z = 0 },
    state: ?*zx.State(State) = null,
    clear_hover: bool = false,
};

var cam_preview: CamPreview = .{};

fn skipState(e: *zx.client.Event.Stateful) void {
    _ = e.state(State);
}

pub fn pinClass(tip: Tip, i: usize, pin: Pin) []const u8 {
    const mascot = pin.mascot != null;
    if (tip.selected == i) return if (mascot) "map-pin has-mascot is-active" else "map-pin is-active";
    if (tip.hovered == i) return if (mascot) "map-pin has-mascot is-hot" else "map-pin is-hot";
    return if (mascot) "map-pin has-mascot" else "map-pin";
}

pub fn collectDockEntries(allocator: zx.Allocator, out: *std.ArrayListUnmanaged(DockEntry), visible: []const Pin) void {
    const index_of = allocator.alloc(?usize, users.users.len) catch return;
    defer allocator.free(index_of);
    @memset(index_of, null);

    for (visible) |pin| {
        if (index_of[pin.user_index]) |ei| {
            out.items[ei].extra_places += 1;
            out.items[ei].place_label = fmtDockPlace(
                allocator,
                out.items[ei].first_city,
                out.items[ei].extra_places,
            ) catch out.items[ei].first_city;
        } else {
            index_of[pin.user_index] = out.items.len;
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

pub fn collectVisiblePinIndices(
    allocator: zx.Allocator,
    out: *std.ArrayListUnmanaged(usize),
    cam: Camera,
    el_w: f64,
    el_h: f64,
) void {
    for (pins, 0..) |pin, i| {
        if (!pinInView(pin, cam, el_w, el_h)) continue;
        out.append(allocator, i) catch {};
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

fn mercatorNorm(lat: f64, lng: f64) struct { x: f64, y: f64 } {
    const lat_c = std.math.clamp(lat, -85.05112878, 85.05112878);
    const sin_y = @sin(lat_c * std.math.pi / 180.0);
    const y = 0.5 - @log((1.0 + sin_y) / (1.0 - sin_y)) / (4.0 * std.math.pi);
    return .{
        .x = (lng + 180.0) / 360.0,
        .y = y,
    };
}

fn project(lat: f64, lng: f64, z: f64) struct { x: f64, y: f64 } {
    const m = mercatorNorm(lat, lng);
    const w = worldSize(z);
    return .{ .x = m.x * w, .y = m.y * w };
}

fn projectPin(pin: Pin, z: f64) struct { x: f64, y: f64 } {
    const w = worldSize(z);
    return .{ .x = pin.mx * w, .y = pin.my * w };
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

pub fn displayTileZoom(z: f64) u8 {
    const clamped = std.math.clamp(z, 0, MAX_Z);
    return @intFromFloat(@min(@floor(clamped + 0.72), MAX_Z));
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
    const pad = TILE_PAD_PX;

    const x0: i32 = @intFromFloat(@floor((cam.x - pad) / tile_span));
    const y0: i32 = @intFromFloat(@floor((cam.y - pad) / tile_span));
    const x1: i32 = @intFromFloat(@floor((cam.x + el_w + pad) / tile_span));
    const y1: i32 = @intFromFloat(@floor((cam.y + el_h + pad) / tile_span));

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
    const p = projectPin(pin, cam.z);
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

fn refreshStageCache() void {
    if (!zx.platform.isClient()) {
        stage_cache = .{ .w = 1280, .h = 800, .left = 0, .top = 0, .valid = true };
        return;
    }
    const document = zx.client.Document.init(zx.allocator);
    const el = document.getElementById("map-stage") catch {
        stage_cache.valid = false;
        return;
    };
    defer el.deinit();
    const w = el.getProperty(f64, "clientWidth") catch 1280;
    const h = el.getProperty(f64, "clientHeight") catch 800;
    var left: f64 = 0;
    var top: f64 = 0;
    if (el.ref.call(js.Object, "getBoundingClientRect", .{})) |rect| {
        defer rect.deinit();
        left = rect.get(f64, "left") catch 0;
        top = rect.get(f64, "top") catch 0;
    } else |_| {}
    stage_cache = .{
        .w = if (w > 0) w else 1280,
        .h = if (h > 0) h else 800,
        .left = left,
        .top = top,
        .valid = true,
    };
}

pub fn stageSize() struct { w: f64, h: f64 } {
    if (!stage_cache.valid) refreshStageCache();
    return .{ .w = stage_cache.w, .h = stage_cache.h };
}

fn focusSearchInput() void {
    if (!zx.platform.isClient()) return;
    const document = zx.client.Document.init(zx.allocator);
    const input = document.getElementById("map-search-input") catch return;
    defer input.deinit();
    input.ref.call(void, "focus", .{}) catch {};
}

fn pointerFocus(client_x: i32, client_y: i32, el_w: f64, el_h: f64) struct { x: f64, y: f64 } {
    if (!stage_cache.valid) refreshStageCache();
    return .{
        .x = std.math.clamp(@as(f64, @floatFromInt(client_x)) - stage_cache.left, 0, el_w),
        .y = std.math.clamp(@as(f64, @floatFromInt(client_y)) - stage_cache.top, 0, el_h),
    };
}

fn capturePointer(pointer_id: i32) void {
    if (!zx.platform.isClient()) return;
    const document = zx.client.Document.init(zx.allocator);
    defer document.deinit();
    const el = document.getElementById("map-stage") catch return;
    defer el.deinit();
    el.ref.call(void, "setPointerCapture", .{pointer_id}) catch {};
}

fn releasePointer(pointer_id: i32) void {
    if (!zx.platform.isClient() or pointer_id == NO_POINTER) return;
    const document = zx.client.Document.init(zx.allocator);
    defer document.deinit();
    const el = document.getElementById("map-stage") catch return;
    defer el.deinit();
    el.ref.call(void, "releasePointerCapture", .{pointer_id}) catch {};
}

fn pinchDistance(d: Drag) f64 {
    const dx = @as(f64, @floatFromInt(d.last2_x - d.last_x));
    const dy = @as(f64, @floatFromInt(d.last2_y - d.last_y));
    return @sqrt(dx * dx + dy * dy);
}

fn isTrackedPointer(d: Drag, pointer_id: i32) bool {
    if (pointer_id == d.pointer_id) return true;
    return d.second_active and pointer_id == d.pointer2_id;
}

fn hasSecondPointer(d: Drag) bool {
    return d.second_active;
}

fn endPinchKeepPan(d: *Drag, lifted_id: i32) void {
    if (lifted_id == d.pointer_id) {
        releasePointer(d.pointer_id);
        d.pointer_id = d.pointer2_id;
        d.last_x = d.last2_x;
        d.last_y = d.last2_y;
    } else {
        releasePointer(d.pointer2_id);
    }
    d.pointer2_id = NO_POINTER;
    d.second_active = false;
    d.last2_x = 0;
    d.last2_y = 0;
    d.last_pinch_dist = 0;
    d.start_x = d.last_x;
    d.start_y = d.last_y;
}

fn setWorldTransform(dx: f64, dy: f64) void {
    setWorldTransformScale(dx, dy, 1.0);
}

fn setWorldTransformScale(dx: f64, dy: f64, scale: f64) void {
    if (!zx.platform.isClient()) return;
    const document = zx.client.Document.init(zx.allocator);
    const el = document.getElementById("map-world") catch return;
    defer el.deinit();
    const style = el.ref.get(js.Object, "style") catch return;
    defer style.deinit();
    style.set("transformOrigin", js.string("0 0")) catch {};
    var buf: [96]u8 = undefined;
    const css = std.fmt.bufPrint(
        &buf,
        "translate3d({d:.2}px,{d:.2}px,0) scale({d:.5})",
        .{ dx, dy, scale },
    ) catch return;
    style.set("transform", js.string(css)) catch {};
}

fn clearWorldTransform() void {
    setWorldTransformScale(0, 0, 1.0);
}

fn setWorldCamPreview(base: Camera, live: Camera) void {
    const scale = std.math.exp2(live.z - base.z);
    const tx = base.x * scale - live.x;
    const ty = base.y * scale - live.y;
    setWorldTransformScale(tx, ty, scale);
}

fn flushCamPreview() void {
    cam_preview.scheduled = false;
    const state = cam_preview.state orelse {
        cam_preview.active = false;
        return;
    };
    if (!cam_preview.active) return;
    var next = state.get();
    next.camera = cam_preview.live;
    next.drag = live_drag;
    if (cam_preview.clear_hover) next.tip.hovered = null;
    cam_preview.active = false;
    cam_preview.clear_hover = false;
    // Commit camera before clearing the live transform so the DOM never
    // briefly shows the pre-gesture camera (black flash / snap-back).
    state.set(next);
    clearWorldTransform();
}

/// Live CSS camera preview without scheduling a DOM commit. Used for pinch so
/// mid-gesture zoom does not rebuild tiles every move.
fn updateCamPreviewLive(state: *zx.State(State), base: Camera, live: Camera, clear_hover: bool) void {
    if (!cam_preview.active) {
        cam_preview.base = base;
        cam_preview.active = true;
    }
    cam_preview.live = live;
    cam_preview.state = state;
    if (clear_hover) cam_preview.clear_hover = true;
    setWorldCamPreview(cam_preview.base, cam_preview.live);
}

fn flushCamPreviewNow() void {
    if (!cam_preview.active) {
        cam_preview.scheduled = false;
        return;
    }
    flushCamPreview();
}

fn visualPanCamera(base: Camera, d: *Drag, el_w: f64, el_h: f64) Camera {
    var preview = base;
    preview.x -= d.world_dx;
    preview.y -= d.world_dy;
    const clamped = clampCamera(preview, el_w, el_h);
    d.world_dx = base.x - clamped.x;
    d.world_dy = base.y - clamped.y;
    setWorldTransform(d.world_dx, d.world_dy);
    return clamped;
}

fn applyWorldPan(cam: *Camera, d: *Drag, el_w: f64, el_h: f64) void {
    if (d.world_dx == 0 and d.world_dy == 0) return;
    var preview = cam.*;
    preview.x -= d.world_dx;
    preview.y -= d.world_dy;
    cam.* = clampCamera(preview, el_w, el_h);
    d.world_dx = 0;
    d.world_dy = 0;
}

fn commitWorldPan(cam: *Camera, d: *Drag, el_w: f64, el_h: f64) void {
    applyWorldPan(cam, d, el_w, el_h);
    clearWorldTransform();
}

fn firstPinForUser(user_index: usize) ?usize {
    for (pins, 0..) |pin, i| {
        if (pin.user_index == user_index) return i;
    }
    return null;
}

fn focusUser(
    state: *State,
    user_index: usize,
    el_w: f64,
    el_h: f64,
) void {
    const pin_i = firstPinForUser(user_index) orelse return;
    const pin = pins[pin_i];
    const p = projectPin(pin, FLY_Z);
    state.camera = clampCamera(.{
        .x = p.x - el_w * 0.5,
        .y = p.y - el_h * 0.45,
        .z = FLY_Z,
    }, el_w, el_h);
    state.tip = .{ .selected = pin_i, .hovered = pin_i };
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
    const state = e.state(State);
    var next = state.get();
    refreshStageCache();
    const size = stageSize();

    if (live_drag.world_dx != 0 or live_drag.world_dy != 0) {
        applyWorldPan(&next.camera, &live_drag, size.w, size.h);
        live_drag = .{};
        next.drag = .{};
        state.set(next);
        clearWorldTransform();
        next = state.get();
    } else {
        live_drag = .{};
        next.drag = .{};
    }

    const we = e.as(zx.client.events.WheelEvent, zx.allocator);
    const committed = clampCamera(next.camera, size.w, size.h);
    const base = if (cam_preview.active) cam_preview.live else committed;
    const focus = pointerFocus(we.client_x, we.client_y, size.w, size.h);

    var delta = we.delta_y;
    if (we.delta_mode == 1) delta *= 16;
    if (we.delta_mode == 2) delta *= size.h;

    const sens = if (we.delta_mode == 0 and @abs(delta) < 48)
        ZOOM_TRACKPAD_SENS
    else
        ZOOM_WHEEL_SENS;
    delta = std.math.clamp(delta, -100.0, 100.0);

    const live = zoomTo(base, base.z - delta * sens, focus.x, focus.y, size.w, size.h);

    cam_preview = .{};
    next.camera = live;
    next.tip.hovered = null;
    state.set(next);
    clearWorldTransform();
}

pub fn onPointerDown(e: *zx.client.Event.Stateful) void {
    if (!zx.platform.isClient()) return;
    const state = e.state(State);
    var next = state.get();
    const pe = e.as(zx.client.events.PointerEvent, zx.allocator);
    const is_touch = std.mem.eql(u8, pe.pointer_type, "touch");
    if (!is_touch and pe.button != 0) return;

    refreshStageCache();
    flushCamPreviewNow();
    next = state.get();

    var d = if (live_drag.active) live_drag else next.drag;
    const size = stageSize();

    if (d.active) {
        if (!hasSecondPointer(d) and pe.pointer_id != d.pointer_id) {
            applyWorldPan(&next.camera, &d, size.w, size.h);
            capturePointer(pe.pointer_id);
            d.pointer2_id = pe.pointer_id;
            d.second_active = true;
            d.last2_x = pe.client_x;
            d.last2_y = pe.client_y;
            d.last_pinch_dist = pinchDistance(d);
            d.moved = true;
            live_drag = d;
            next.drag = d;
            next.tip.hovered = null;
            state.set(next);
            clearWorldTransform();
        }
        return;
    }

    capturePointer(pe.pointer_id);
    d = .{
        .active = true,
        .moved = false,
        .last_x = pe.client_x,
        .last_y = pe.client_y,
        .start_x = pe.client_x,
        .start_y = pe.client_y,
        .pointer_id = pe.pointer_id,
    };
    live_drag = d;
    next.drag = d;
    state.set(next);
}

pub fn onPointerMove(e: *zx.client.Event.Stateful) void {
    if (!zx.platform.isClient()) return;
    const state = e.state(State);
    var next = state.get();
    var d = if (live_drag.active) live_drag else next.drag;
    const pe = e.as(zx.client.events.PointerEvent, zx.allocator);
    const size = stageSize();
    var cam = if (cam_preview.active) cam_preview.live else clampCamera(next.camera, size.w, size.h);

    if (d.active) {
        if (hasSecondPointer(d)) {
            if (!isTrackedPointer(d, pe.pointer_id)) return;

            const old_mid_x = @as(f64, @floatFromInt(d.last_x + d.last2_x)) * 0.5;
            const old_mid_y = @as(f64, @floatFromInt(d.last_y + d.last2_y)) * 0.5;
            const old_dist = d.last_pinch_dist;

            if (pe.pointer_id == d.pointer_id) {
                d.last_x = pe.client_x;
                d.last_y = pe.client_y;
            } else {
                d.last2_x = pe.client_x;
                d.last2_y = pe.client_y;
            }

            const new_dist = pinchDistance(d);
            const new_mid_x = @as(f64, @floatFromInt(d.last_x + d.last2_x)) * 0.5;
            const new_mid_y = @as(f64, @floatFromInt(d.last_y + d.last2_y)) * 0.5;

            e.preventDefault();
            if (old_dist >= MIN_PINCH_DIST and new_dist >= MIN_PINCH_DIST) {
                const focus = pointerFocus(
                    @intFromFloat(old_mid_x),
                    @intFromFloat(old_mid_y),
                    size.w,
                    size.h,
                );
                const dz = std.math.log2(new_dist / old_dist);
                cam = zoomTo(cam, cam.z + dz, focus.x, focus.y, size.w, size.h);
            }
            cam.x -= new_mid_x - old_mid_x;
            cam.y -= new_mid_y - old_mid_y;
            cam = clampCamera(cam, size.w, size.h);
            d.last_pinch_dist = new_dist;
            live_drag = d;
            updateCamPreviewLive(state, clampCamera(next.camera, size.w, size.h), cam, true);
            return;
        }

        if (pe.pointer_id != d.pointer_id) return;
        const is_touch = std.mem.eql(u8, pe.pointer_type, "touch");
        if (!is_touch and (pe.buttons & 1) == 0) {
            flushCamPreviewNow();
            next = state.get();
            applyWorldPan(&next.camera, &d, size.w, size.h);
            releasePointer(d.pointer_id);
            live_drag = .{};
            next.drag = .{};
            next.camera = clampCamera(next.camera, size.w, size.h);
            state.set(next);
            clearWorldTransform();
            return;
        }
        const adx = @abs(pe.client_x - d.start_x);
        const ady = @abs(pe.client_y - d.start_y);
        if (adx > CLICK_SLOP_PX or ady > CLICK_SLOP_PX) d.moved = true;

        if (d.moved) {
            e.preventDefault();
            // Only flush a pending wheel preview once when the pan starts.
            if (cam_preview.active) {
                flushCamPreviewNow();
                next = state.get();
            }
            cam = clampCamera(next.camera, size.w, size.h);
            d.world_dx += @as(f64, @floatFromInt(pe.client_x - d.last_x));
            d.world_dy += @as(f64, @floatFromInt(pe.client_y - d.last_y));
            d.last_x = pe.client_x;
            d.last_y = pe.client_y;
            _ = visualPanCamera(cam, &d, size.w, size.h);
            live_drag = d;

            if (@abs(d.world_dx) >= PAN_COMMIT_PX or @abs(d.world_dy) >= PAN_COMMIT_PX) {
                applyWorldPan(&next.camera, &d, size.w, size.h);
                live_drag = d;
                next.drag = d;
                next.tip.hovered = null;
                state.set(next);
                clearWorldTransform();
            }
            return;
        }

        d.last_x = pe.client_x;
        d.last_y = pe.client_y;
        live_drag = d;
        return;
    }

    const focus = pointerFocus(pe.client_x, pe.client_y, size.w, size.h);
    const hovered = hitPinIndex(focus.x, focus.y, cam);
    if (next.tip.hovered == hovered) return;
    next.tip.hovered = hovered;
    state.set(next);
}

pub fn onPointerUp(e: *zx.client.Event.Stateful) void {
    if (!zx.platform.isClient()) return;
    const state = e.state(State);
    flushCamPreviewNow();
    var next = state.get();
    var d = if (live_drag.active) live_drag else next.drag;
    if (!d.active) return;

    const pe = e.as(zx.client.events.PointerEvent, zx.allocator);
    if (!isTrackedPointer(d, pe.pointer_id)) return;

    const size = stageSize();

    // One finger of a pinch lifted → keep panning with the remaining finger.
    if (hasSecondPointer(d)) {
        endPinchKeepPan(&d, pe.pointer_id);
        live_drag = d;
        next.drag = d;
        state.set(next);
        return;
    }

    releasePointer(d.pointer_id);
    applyWorldPan(&next.camera, &d, size.w, size.h);

    if (!d.moved) {
        const cam = clampCamera(next.camera, size.w, size.h);
        const focus = pointerFocus(pe.client_x, pe.client_y, size.w, size.h);
        next.tip.selected = hitPinIndex(focus.x, focus.y, cam);
        next.tip.hovered = next.tip.selected;
    }
    live_drag = .{};
    next.drag = .{};
    state.set(next);
    clearWorldTransform();
}

pub fn onPointerLeave(e: *zx.client.Event.Stateful) void {
    if (!zx.platform.isClient()) return;
    const state = e.state(State);
    var next = state.get();
    if (next.tip.hovered == null) return;
    next.tip.hovered = null;
    state.set(next);
}

pub fn onControlsPointer(e: *zx.client.Event.Stateful) void {
    e.stopPropagation();
    skipState(e);
}

pub fn onDockWheel(e: *zx.client.Event.Stateful) void {
    e.stopPropagation();
    skipState(e);
}

pub fn onTipPointer(e: *zx.client.Event.Stateful) void {
    e.stopPropagation();
    skipState(e);
}

pub fn onTipClose(e: *zx.client.Event.Stateful) void {
    e.stopPropagation();
    const state = e.state(State);
    var next = state.get();
    next.tip = .{};
    state.set(next);
}

pub fn onZoomIn(e: *zx.client.Event.Stateful) void {
    if (!zx.platform.isClient()) return;
    const state = e.state(State);
    flushCamPreviewNow();
    var next = state.get();
    refreshStageCache();
    const size = stageSize();
    applyWorldPan(&next.camera, &live_drag, size.w, size.h);
    live_drag = .{};
    const cam = clampCamera(next.camera, size.w, size.h);
    next.camera = zoomTo(cam, cam.z + ZOOM_STEP_BUTTON, size.w * 0.5, size.h * 0.5, size.w, size.h);
    next.drag = .{};
    state.set(next);
    clearWorldTransform();
}

pub fn onZoomOut(e: *zx.client.Event.Stateful) void {
    if (!zx.platform.isClient()) return;
    const state = e.state(State);
    flushCamPreviewNow();
    var next = state.get();
    refreshStageCache();
    const size = stageSize();
    applyWorldPan(&next.camera, &live_drag, size.w, size.h);
    live_drag = .{};
    const cam = clampCamera(next.camera, size.w, size.h);
    next.camera = zoomTo(cam, cam.z - ZOOM_STEP_BUTTON, size.w * 0.5, size.h * 0.5, size.w, size.h);
    next.drag = .{};
    state.set(next);
    clearWorldTransform();
}

pub fn onReset(e: *zx.client.Event.Stateful) void {
    if (!zx.platform.isClient()) return;
    flushCamPreviewNow();
    live_drag = .{};
    clearWorldTransform();
    refreshStageCache();
    const size = stageSize();
    e.state(State).set(.{ .camera = initialCamera(size.w, size.h) });
}

pub fn onSearchToggle(e: *zx.client.Event.Stateful) void {
    e.stopPropagation();
    if (!zx.platform.isClient()) return;
    const state = e.state(State);
    var next = state.get();
    next.search.open = !next.search.open;
    if (!next.search.open) next.search.len = 0;
    if (next.search.open) next.join.open = false;
    state.set(next);
    if (next.search.open) focusSearchInput();
}

pub fn onSearchInput(e: *zx.client.Event.Stateful) void {
    e.stopPropagation();
    if (!zx.platform.isClient()) return;
    const state = e.state(State);
    const raw = e.value() orelse "";
    var next = state.get();
    const n = @min(raw.len, next.search.query.len);
    if (n > 0) @memcpy(next.search.query[0..n], raw[0..n]);
    next.search.len = n;
    next.search.open = true;
    state.set(next);
}

pub fn onSearchClear(e: *zx.client.Event.Stateful) void {
    e.stopPropagation();
    if (!zx.platform.isClient()) return;
    const state = e.state(State);
    var next = state.get();
    next.search = .{ .open = true };
    state.set(next);
}

pub fn onSelectUser(e: *zx.client.Event.Stateful) void {
    e.stopPropagation();
    e.preventDefault();
    if (!zx.platform.isClient()) return;
    const state = e.state(State);
    var next = state.get();

    const raw = e.value() orelse return;
    const user_index = std.fmt.parseInt(usize, raw, 10) catch return;
    const size = stageSize();
    focusUser(&next, user_index, size.w, size.h);
    next.search = .{};
    state.set(next);
}

fn focusJoinUsername() void {
    if (!zx.platform.isClient()) return;
    const document = zx.client.Document.init(zx.allocator);
    const input = document.getElementById("map-join-username") catch return;
    defer input.deinit();
    input.ref.call(void, "focus", .{}) catch {};
}

fn fieldName(e: *zx.client.Event.Stateful) ?[]const u8 {
    const event = e.getEvent();
    const current = event.ref.get(js.Object, "currentTarget") catch return null;
    defer current.deinit();
    return current.getAlloc(js.String, zx.allocator, "name") catch null;
}

pub fn onJoinToggle(e: *zx.client.Event.Stateful) void {
    e.stopPropagation();
    if (!zx.platform.isClient()) return;
    const state = e.state(State);
    var next = state.get();
    next.join.open = !next.join.open;
    if (next.join.open) {
        next.search.open = false;
        next.search.len = 0;
        next.join.err = .none;
    }
    state.set(next);
    if (next.join.open) focusJoinUsername();
}

pub fn onJoinUsername(e: *zx.client.Event.Stateful) void {
    e.stopPropagation();
    if (!zx.platform.isClient()) return;
    const state = e.state(State);
    var next = state.get();
    next.join.username.set(e.value() orelse "");
    next.join.err = .none;
    state.set(next);
}

pub fn onJoinMode(e: *zx.client.Event.Stateful) void {
    e.stopPropagation();
    if (!zx.platform.isClient()) return;
    const state = e.state(State);
    var next = state.get();
    const raw = e.value() orelse return;
    next.join.location_mode = std.meta.stringToEnum(JoinLocationMode, raw) orelse return;
    next.join.err = .none;
    if (next.join.location_mode != .city) next.join.city_index = null;
    state.set(next);
}

pub fn onJoinCity(e: *zx.client.Event.Stateful) void {
    e.stopPropagation();
    if (!zx.platform.isClient()) return;
    const state = e.state(State);
    var next = state.get();
    const raw = e.value() orelse return;
    if (raw.len == 0) {
        next.join.city_index = null;
    } else {
        next.join.city_index = std.fmt.parseInt(usize, raw, 10) catch return;
        if (next.join.city_index.? >= cities.len) next.join.city_index = null;
    }
    next.join.err = .none;
    state.set(next);
}

pub fn onJoinLat(e: *zx.client.Event.Stateful) void {
    e.stopPropagation();
    if (!zx.platform.isClient()) return;
    const state = e.state(State);
    var next = state.get();
    next.join.lat.set(e.value() orelse "");
    next.join.err = .none;
    state.set(next);
}

pub fn onJoinLng(e: *zx.client.Event.Stateful) void {
    e.stopPropagation();
    if (!zx.platform.isClient()) return;
    const state = e.state(State);
    var next = state.get();
    next.join.lng.set(e.value() orelse "");
    next.join.err = .none;
    state.set(next);
}

pub fn onJoinDetect(e: *zx.client.Event.Stateful) void {
    e.stopPropagation();
    e.preventDefault();
    if (!zx.platform.isClient()) return;
    const state = e.state(State);
    var next = state.get();
    next.join.err = .none;
    state.set(next);
    _ = zx.client.eval(void,
        \\navigator.geolocation.getCurrentPosition(function(p){
        \\  var lat=document.getElementById('map-join-lat');
        \\  var lng=document.getElementById('map-join-lng');
        \\  if(!lat||!lng)return;
        \\  lat.value=String(p.coords.latitude);
        \\  lng.value=String(p.coords.longitude);
        \\  lat.dispatchEvent(new Event('input',{bubbles:true}));
        \\  lng.dispatchEvent(new Event('input',{bubbles:true}));
        \\},function(){
        \\  var err=document.getElementById('map-join-geo-err');
        \\  if(err){err.hidden=false;}
        \\},{enableHighAccuracy:false,timeout:10000});
    ) catch {};
}

pub fn onJoinAddLink(e: *zx.client.Event.Stateful) void {
    e.stopPropagation();
    e.preventDefault();
    if (!zx.platform.isClient()) return;
    const state = e.state(State);
    var next = state.get();
    if (next.join.link_count < MAX_JOIN_LINKS) next.join.link_count += 1;
    next.join.err = .none;
    state.set(next);
}

pub fn onJoinRemoveLink(e: *zx.client.Event.Stateful) void {
    e.stopPropagation();
    e.preventDefault();
    if (!zx.platform.isClient()) return;
    const state = e.state(State);
    var next = state.get();
    const raw = e.value() orelse return;
    const idx = std.fmt.parseInt(usize, raw, 10) catch return;
    if (idx >= next.join.link_count) return;
    var i = idx;
    while (i + 1 < next.join.link_count) : (i += 1) {
        next.join.links[i] = next.join.links[i + 1];
    }
    next.join.links[next.join.link_count - 1] = .{};
    next.join.link_count -= 1;
    if (next.join.link_count == 0) next.join.link_count = 1;
    next.join.err = .none;
    state.set(next);
}

pub fn onJoinLinkLabel(e: *zx.client.Event.Stateful) void {
    e.stopPropagation();
    if (!zx.platform.isClient()) return;
    const idx = std.fmt.parseInt(usize, fieldName(e) orelse return, 10) catch return;
    if (idx >= MAX_JOIN_LINKS) return;
    const state = e.state(State);
    var next = state.get();
    next.join.links[idx].label.set(e.value() orelse "");
    next.join.err = .none;
    state.set(next);
}

pub fn onJoinLinkHref(e: *zx.client.Event.Stateful) void {
    e.stopPropagation();
    if (!zx.platform.isClient()) return;
    const idx = std.fmt.parseInt(usize, fieldName(e) orelse return, 10) catch return;
    if (idx >= MAX_JOIN_LINKS) return;
    const state = e.state(State);
    var next = state.get();
    next.join.links[idx].href.set(e.value() orelse "");
    next.join.err = .none;
    state.set(next);
}

fn trimAscii(s: []const u8) []const u8 {
    var start: usize = 0;
    var end = s.len;
    while (start < end and std.ascii.isWhitespace(s[start])) start += 1;
    while (end > start and std.ascii.isWhitespace(s[end - 1])) end -= 1;
    return s[start..end];
}

fn isValidNick(s: []const u8) bool {
    if (s.len == 0 or s.len > 64) return false;
    for (s) |c| {
        const ok = std.ascii.isAlphanumeric(c) or c == '-' or c == '_' or c == '.' or c == ' ';
        if (!ok) return false;
    }
    return true;
}

fn appendJsonString(out: *std.ArrayListUnmanaged(u8), allocator: zx.Allocator, s: []const u8) !void {
    try out.append(allocator, '"');
    for (s) |c| {
        switch (c) {
            '"' => try out.appendSlice(allocator, "\\\""),
            '\\' => try out.appendSlice(allocator, "\\\\"),
            '\n' => try out.appendSlice(allocator, "\\n"),
            '\r' => try out.appendSlice(allocator, "\\r"),
            '\t' => try out.appendSlice(allocator, "\\t"),
            else => {
                if (c < 0x20) {
                    var buf: [6]u8 = undefined;
                    const piece = try std.fmt.bufPrint(&buf, "\\u{x:0>4}", .{c});
                    try out.appendSlice(allocator, piece);
                } else {
                    try out.append(allocator, c);
                }
            },
        }
    }
    try out.append(allocator, '"');
}

fn percentEncode(allocator: zx.Allocator, s: []const u8) ![]const u8 {
    var out: std.ArrayListUnmanaged(u8) = .empty;
    errdefer out.deinit(allocator);
    for (s) |c| {
        const unreserved = std.ascii.isAlphanumeric(c) or c == '-' or c == '_' or c == '.' or c == '~';
        if (unreserved) {
            try out.append(allocator, c);
        } else {
            var buf: [3]u8 = undefined;
            const piece = try std.fmt.bufPrint(&buf, "%{X:0>2}", .{c});
            try out.appendSlice(allocator, piece);
        }
    }
    return try out.toOwnedSlice(allocator);
}

fn sanitizeFilename(allocator: zx.Allocator, nick: []const u8) ![]const u8 {
    var out: std.ArrayListUnmanaged(u8) = .empty;
    errdefer out.deinit(allocator);
    for (nick) |c| {
        if (std.ascii.isAlphanumeric(c) or c == '-' or c == '_' or c == '.') {
            try out.append(allocator, c);
        } else if (c == ' ') {
            try out.append(allocator, '-');
        }
    }
    if (out.items.len == 0) try out.appendSlice(allocator, "zigiana");
    return try out.toOwnedSlice(allocator);
}

const JoinCoords = struct { lat: f64, lng: f64 };

fn resolveJoinCoords(join: Join) ?JoinCoords {
    return switch (join.location_mode) {
        .city => blk: {
            const idx = join.city_index orelse break :blk null;
            if (idx >= cities.len) break :blk null;
            break :blk .{ .lat = cities[idx].lat, .lng = cities[idx].lng };
        },
        .automatic, .manual => blk: {
            const lat = std.fmt.parseFloat(f64, trimAscii(join.lat.text())) catch break :blk null;
            const lng = std.fmt.parseFloat(f64, trimAscii(join.lng.text())) catch break :blk null;
            if (!std.math.isFinite(lat) or !std.math.isFinite(lng)) break :blk null;
            if (lat < -90 or lat > 90 or lng < -180 or lng > 180) break :blk null;
            break :blk .{ .lat = lat, .lng = lng };
        },
    };
}

// Manually serializing to avoid including std.json into the wasm which bloats the size
fn buildPersonJson(allocator: zx.Allocator, join: Join, coords: JoinCoords) ![]const u8 {
    var out: std.ArrayListUnmanaged(u8) = .empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, "{\n  \"nick\": ");
    try appendJsonString(&out, allocator, trimAscii(join.username.text()));
    try out.appendSlice(allocator, ",\n  \"coordinates\": [\n    ");
    var num: [64]u8 = undefined;
    try out.appendSlice(allocator, try std.fmt.bufPrint(&num, "{d}", .{coords.lat}));
    try out.appendSlice(allocator, ",\n    ");
    try out.appendSlice(allocator, try std.fmt.bufPrint(&num, "{d}", .{coords.lng}));
    try out.appendSlice(allocator, "\n  ]");

    var first_link = true;
    for (join.links[0..join.link_count]) |link| {
        const label = trimAscii(link.label.text());
        const href = trimAscii(link.href.text());
        if (label.len == 0 and href.len == 0) continue;
        if (label.len == 0 or href.len == 0) return error.IncompleteLink;
        if (first_link) {
            try out.appendSlice(allocator, ",\n  \"links\": {\n");
            first_link = false;
        } else {
            try out.appendSlice(allocator, ",\n");
        }
        try out.appendSlice(allocator, "    ");
        try appendJsonString(&out, allocator, label);
        try out.appendSlice(allocator, ": ");
        try appendJsonString(&out, allocator, href);
    }
    if (!first_link) try out.appendSlice(allocator, "\n  }");
    try out.appendSlice(allocator, "\n}\n");
    return try out.toOwnedSlice(allocator);
}

fn openGithubNewFile(allocator: zx.Allocator, filename: []const u8, contents: []const u8) !void {
    const enc_name = try percentEncode(allocator, filename);
    const enc_value = try percentEncode(allocator, contents);
    const url = try std.fmt.allocPrint(
        allocator,
        "https://github.com/zig-community/user-map/new/master/people?filename={s}&value={s}",
        .{ enc_name, enc_value },
    );
    const win = try js.global.get(js.Object, "window");
    defer win.deinit();
    try win.call(void, "open", .{ js.string(url), js.string("_blank"), js.string("noopener,noreferrer") });
}

pub fn onJoinSubmit(e: *zx.client.Event.Stateful) void {
    e.stopPropagation();
    e.preventDefault();
    if (!zx.platform.isClient()) return;
    const state = e.state(State);
    var next = state.get();
    const nick = trimAscii(next.join.username.text());
    if (!isValidNick(nick)) {
        next.join.err = .username;
        state.set(next);
        return;
    }
    const coords = resolveJoinCoords(next.join) orelse {
        next.join.err = .location;
        state.set(next);
        return;
    };
    for (next.join.links[0..next.join.link_count]) |link| {
        const label = trimAscii(link.label.text());
        const href = trimAscii(link.href.text());
        if ((label.len == 0) != (href.len == 0)) {
            next.join.err = .links;
            state.set(next);
            return;
        }
    }

    const json = buildPersonJson(zx.allocator, next.join, coords) catch {
        next.join.err = .links;
        state.set(next);
        return;
    };
    const base = sanitizeFilename(zx.allocator, nick) catch {
        next.join.err = .username;
        state.set(next);
        return;
    };
    const filename = std.fmt.allocPrint(zx.allocator, "{s}.json", .{base}) catch {
        next.join.err = .username;
        state.set(next);
        return;
    };
    openGithubNewFile(zx.allocator, filename, json) catch {
        next.join.err = .links;
        state.set(next);
        return;
    };
    next.join.err = .none;
    state.set(next);
}

pub fn joinErrorText(err: JoinError) []const u8 {
    return switch (err) {
        .none => "",
        .username => "Enter a username (letters, numbers, spaces, - _ .)",
        .location => "Pick a city or enter valid latitude and longitude",
        .links => "Each link needs both a label and a URL",
        .geolocation => "Could not detect your location",
    };
}

pub fn fmtFieldValue(allocator: zx.Allocator, field: JoinField) []const u8 {
    return std.fmt.allocPrint(allocator, "{s}", .{field.text()}) catch "";
}

pub fn fmtCityOption(allocator: zx.Allocator, index: usize) []const u8 {
    return std.fmt.allocPrint(allocator, "{d}", .{index}) catch "0";
}

pub fn fmtCityLabel(allocator: zx.Allocator, city: City) []const u8 {
    return std.fmt.allocPrint(allocator, "{s}, {s}", .{ city.name, city.country }) catch city.name;
}

pub fn fmtTileSrc(allocator: zx.Allocator, tile: TileView) []const u8 {
    return std.fmt.allocPrint(
        allocator,
        "https://basemaps.cartocdn.com/rastertiles/voyager/{d}/{d}/{d}.png",
        .{ tile.z, tile.x, tile.y },
    ) catch "";
}

pub fn fmtTileKey(allocator: zx.Allocator, tile: TileView) []const u8 {
    return std.fmt.allocPrint(allocator, "{d}/{d}/{d}", .{ tile.z, tile.x, tile.y }) catch "";
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
