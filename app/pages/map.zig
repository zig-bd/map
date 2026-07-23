const std = @import("std");
const zx = @import("zx");
const types = @import("types");

const js = zx.client.js;

pub const TILE: f64 = 256;
pub const MIN_Z: f64 = 2.0;
pub const MAX_Z: f64 = 18.0;
pub const ZOOM_STEP_BUTTON: f64 = 0.55;
pub const ZOOM_WHEEL_SENS: f64 = 0.0020;
pub const ZOOM_TRACKPAD_SENS: f64 = 0.0055;
pub const HIT_PX: f64 = 18;
pub const CLICK_SLOP_PX: i32 = 6;
pub const MAX_JOIN_LINKS: usize = 4;

const FLY_Z: f64 = 7.0;
const SEARCH_RESULT_CAP: usize = 12;
const MIN_PINCH_DIST: f64 = 16.0;
const PAN_COMMIT_PX: f64 = 384.0;
const TILE_PAD_PX: f64 = 512.0;
/// iOS Safari can expose negative pointerIds.
const NO_POINTER: i32 = -1;

pub const Link = types.Link;
pub const Place = types.Place;
pub const Mascot = types.Mascot;
pub const Avatar = types.Avatar;
pub const User = types.User;
pub const Event = types.Event;
pub const Mirror = types.Mirror;
pub const LocationKind = types.LocationKind;
pub const Location = types.Location;

pub const Pin = struct {
    location_index: usize,
    username: []const u8,
    city: []const u8,
    lat: f64,
    lng: f64,
    mx: f64,
    my: f64,
    links: []const Link,
    mascot: ?Mascot = null,
    kind: LocationKind = .user,
};

pub const Camera = struct {
    x: f64,
    y: f64,
    z: f64,
};

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
    location_index: usize,
    username: []const u8,
    kind: LocationKind = .user,
};

pub const LocationsData = struct {
    users: []const User = &.{},
    events: []const Event = &.{},
    mirrors: []const Mirror = &.{},
    pins: []const Pin = &.{},
    ready: bool = false,
};

/// Component-owned state exposed to the async fetch callback.
pub var places: *zx.State(Places) = undefined;
var places_fetch_started = false;

pub var locations: *zx.State(LocationsData) = undefined;
var locations_fetch_started = false;

pub fn getPins() []const Pin {
    return locations.get().pins;
}

pub fn locationCount() usize {
    const d = locations.get();
    return d.users.len + d.events.len + d.mirrors.len;
}

pub fn locationAt(index: usize) Location {
    const d = locations.get();
    if (index < d.users.len) return .{ .user = d.users[index] };
    const after_users = index - d.users.len;
    if (after_users < d.events.len) return .{ .event = d.events[after_users] };
    return .{ .mirror = d.mirrors[after_users - d.events.len] };
}

pub fn initPlaces(state: *zx.State(Places), load: bool) []const City {
    if (zx.platform.isClient()) {
        places = state;
        if (load) fetchPlaces();
    }
    return state.get().places;
}

pub fn initLocations(state: *zx.State(LocationsData), load: bool) LocationsData {
    if (zx.platform.isClient()) {
        locations = state;
        if (load) fetchLocations();
    }
    return state.get();
}

fn fetchPlaces() void {
    if (!zx.platform.isClient() or places_fetch_started or places.get().places.len > 0) return;
    places_fetch_started = true;
    _ = zx.fetch(.wasm(&onPlacesFetch), zx.allocator, "/places.json", .{}) catch {
        places_fetch_started = false;
    };
}

fn fetchLocations() void {
    if (!zx.platform.isClient() or locations_fetch_started or locations.get().ready) return;
    locations_fetch_started = true;
    _ = zx.fetch(.wasm(&onLocationsFetch), zx.allocator, "/locations.json", .{}) catch {
        locations_fetch_started = false;
    };
}

fn onPlacesFetch(response: ?*zx.Fetch.Response, err: ?zx.Fetch.FetchError) void {
    if (err != null) {
        places_fetch_started = false;
        return;
    }
    const res = response orelse {
        places_fetch_started = false;
        return;
    };
    defer res.deinit();
    if (!res.ok()) {
        places_fetch_started = false;
        return;
    }
    const text = res.text() catch {
        places_fetch_started = false;
        return;
    };
    const loaded = zx.util.zxon.parse(Places, zx.allocator, text, .{}) catch {
        places_fetch_started = false;
        return;
    };
    places_fetch_started = false;
    places.set(loaded);
}

fn onLocationsFetch(response: ?*zx.Fetch.Response, err: ?zx.Fetch.FetchError) void {
    if (err != null) {
        locations_fetch_started = false;
        return;
    }
    const res = response orelse {
        locations_fetch_started = false;
        return;
    };
    defer res.deinit();
    if (!res.ok()) {
        locations_fetch_started = false;
        return;
    }
    const text = res.text() catch {
        locations_fetch_started = false;
        return;
    };
    var data = zx.util.zxon.parse(LocationsData, zx.allocator, text, .{}) catch {
        locations_fetch_started = false;
        return;
    };
    data.pins = allocPins(data) catch {
        locations_fetch_started = false;
        return;
    };
    data.ready = true;
    locations_fetch_started = false;
    locations.set(data);
}

fn allocPins(data: LocationsData) ![]const Pin {
    var pin_n: usize = 0;
    for (data.users) |u| pin_n += u.places.len;
    for (data.events) |e| pin_n += e.places.len;
    for (data.mirrors) |m| pin_n += m.places.len;

    const pin_arr = try zx.allocator.alloc(Pin, pin_n);
    var pi: usize = 0;
    var li: usize = 0;
    for (data.users) |u| {
        for (u.places) |place| {
            pin_arr[pi] = makePin(li, u.username, place, u.links, if (u.avatar) |a| a.mascot else null, .user);
            pi += 1;
        }
        li += 1;
    }
    for (data.events) |e| {
        for (e.places) |place| {
            pin_arr[pi] = makePin(li, e.name, place, e.links, null, .event);
            pi += 1;
        }
        li += 1;
    }
    for (data.mirrors) |m| {
        for (m.places) |place| {
            pin_arr[pi] = makePin(li, m.name, place, m.links, null, .mirror);
            pi += 1;
        }
        li += 1;
    }
    return pin_arr;
}

fn makePin(
    location_index: usize,
    name: []const u8,
    place: Place,
    links: []const Link,
    mascot: ?Mascot,
    kind: LocationKind,
) Pin {
    const m = mercatorNorm(place.lat, place.lng);
    return .{
        .location_index = location_index,
        .username = name,
        .city = place.city,
        .lat = place.lat,
        .lng = place.lng,
        .mx = m.x,
        .my = m.y,
        .links = links,
        .mascot = mascot,
        .kind = kind,
    };
}

fn cities() []const City {
    return places.get().places;
}

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
    base: Camera = .{ .x = 0, .y = 0, .z = 0 },
    live: Camera = .{ .x = 0, .y = 0, .z = 0 },
    state: ?*zx.State(State) = null,
    clear_hover: bool = false,
};

var cam_preview: CamPreview = .{};

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

pub fn initialCamera(el_w: f64, el_h: f64) Camera {
    const z = @max(effectiveMinZoom(el_w, el_h), MIN_Z + 0.35);
    const w = worldSize(z);
    return clampCamera(.{
        .x = (w - el_w) * 0.5,
        .y = (w - el_h) * 0.42,
        .z = z,
    }, el_w, el_h);
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

pub fn screenPos(pin: Pin, cam: Camera) struct { x: f64, y: f64 } {
    const p = projectPin(pin, cam.z);
    return .{ .x = p.x - cam.x, .y = p.y - cam.y };
}

pub fn pinInView(pin: Pin, cam: Camera, el_w: f64, el_h: f64) bool {
    const p = screenPos(pin, cam);
    return p.x >= -HIT_PX and p.x <= el_w + HIT_PX and p.y >= -HIT_PX and p.y <= el_h + HIT_PX;
}

fn hitPinIndex(sx: f64, sy: f64, cam: Camera) ?usize {
    var best_i: ?usize = null;
    var best_d: f64 = HIT_PX * HIT_PX;
    for (getPins(), 0..) |pin, i| {
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

pub fn collectVisiblePinIndices(
    allocator: zx.Allocator,
    out: *std.ArrayListUnmanaged(usize),
    cam: Camera,
    el_w: f64,
    el_h: f64,
) void {
    for (getPins(), 0..) |pin, i| {
        if (!pinInView(pin, cam, el_w, el_h)) continue;
        out.append(allocator, i) catch {};
    }
}

pub fn collectDockEntries(
    allocator: zx.Allocator,
    out: *std.ArrayListUnmanaged(DockEntry),
    pins: []const Pin,
    visible_indices: []const usize,
) void {
    const seen = allocator.alloc(bool, locationCount()) catch return;
    defer allocator.free(seen);
    @memset(seen, false);

    for (visible_indices) |pin_i| {
        const pin = pins[pin_i];
        if (seen[pin.location_index]) continue;
        seen[pin.location_index] = true;
        out.append(allocator, .{
            .location_index = pin.location_index,
            .username = pin.username,
            .kind = pin.kind,
        }) catch {};
    }
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
    var li: usize = 0;
    while (li < locationCount()) : (li += 1) {
        if (!containsIgnoreCase(locationAt(li).name(), query)) continue;
        out.append(allocator, li) catch {};
        if (out.items.len >= SEARCH_RESULT_CAP) break;
    }
}

pub fn pinClass(tip: Tip, i: usize, pin: Pin) []const u8 {
    const mascot = pin.mascot != null;
    if (mascot) {
        if (tip.selected == i) return "map-pin has-mascot is-active";
        if (tip.hovered == i) return "map-pin has-mascot is-hot";
        return "map-pin has-mascot";
    }
    if (tip.selected == i) return switch (pin.kind) {
        .user => "map-pin is-active",
        .event => "map-pin is-event is-active",
        .mirror => "map-pin is-mirror is-active",
    };
    if (tip.hovered == i) return switch (pin.kind) {
        .user => "map-pin is-hot",
        .event => "map-pin is-event is-hot",
        .mirror => "map-pin is-mirror is-hot",
    };
    return switch (pin.kind) {
        .user => "map-pin",
        .event => "map-pin is-event",
        .mirror => "map-pin is-mirror",
    };
}

pub fn kindDotClass(kind: LocationKind) []const u8 {
    return switch (kind) {
        .user => "map-kind-dot is-user",
        .event => "map-kind-dot is-event",
        .mirror => "map-kind-dot is-mirror",
    };
}

pub fn searchHitClass(kind: LocationKind) []const u8 {
    return switch (kind) {
        .user => "map-search-hit",
        .event => "map-search-hit is-event",
        .mirror => "map-search-hit is-mirror",
    };
}

pub fn searchKindClass(kind: LocationKind) []const u8 {
    return switch (kind) {
        .user => "map-search-kind",
        .event => "map-search-kind is-event",
        .mirror => "map-search-kind is-mirror",
    };
}

pub fn kindLabel(kind: LocationKind) []const u8 {
    return switch (kind) {
        .user => "user",
        .event => "event",
        .mirror => "mirror",
    };
}

fn firstPinForLocation(location_index: usize) ?usize {
    for (getPins(), 0..) |pin, i| {
        if (pin.location_index == location_index) return i;
    }
    return null;
}

fn focusUser(state: *State, user_index: usize, el_w: f64, el_h: f64) void {
    const pin_i = firstPinForLocation(user_index) orelse return;
    const pin = getPins()[pin_i];
    const p = projectPin(pin, FLY_Z);
    state.camera = clampCamera(.{
        .x = p.x - el_w * 0.5,
        .y = p.y - el_h * 0.45,
        .z = FLY_Z,
    }, el_w, el_h);
    state.tip = .{ .selected = pin_i, .hovered = pin_i };
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

fn pointerFocus(client_x: i32, client_y: i32, el_w: f64, el_h: f64) struct { x: f64, y: f64 } {
    if (!stage_cache.valid) refreshStageCache();
    return .{
        .x = std.math.clamp(@as(f64, @floatFromInt(client_x)) - stage_cache.left, 0, el_w),
        .y = std.math.clamp(@as(f64, @floatFromInt(client_y)) - stage_cache.top, 0, el_h),
    };
}

fn focusElement(id: []const u8) void {
    if (!zx.platform.isClient()) return;
    const document = zx.client.Document.init(zx.allocator);
    const input = document.getElementById(id) catch return;
    defer input.deinit();
    input.ref.call(void, "focus", .{}) catch {};
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

fn setWorldTransform(dx: f64, dy: f64) void {
    setWorldTransformScale(dx, dy, 1.0);
}

fn setWorldCamPreview(base: Camera, live: Camera) void {
    const scale = std.math.exp2(live.z - base.z);
    setWorldTransformScale(base.x * scale - live.x, base.y * scale - live.y, scale);
}

fn flushCamPreview() void {
    const state = cam_preview.state orelse {
        cam_preview = .{};
        return;
    };
    if (!cam_preview.active) {
        cam_preview = .{};
        return;
    }
    var next = state.get();
    next.camera = cam_preview.live;
    next.drag = live_drag;
    if (cam_preview.clear_hover) next.tip.hovered = null;
    cam_preview = .{};
    state.set(next);
    clearWorldTransform();
}

fn flushCamPreviewNow() void {
    if (!cam_preview.active) return;
    flushCamPreview();
}

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

fn activeDrag(next: State) Drag {
    return if (live_drag.active) live_drag else next.drag;
}

fn clearDrag(next: *State) void {
    live_drag = .{};
    next.drag = .{};
}

fn publishWithClear(state: *zx.State(State), next: State) void {
    state.set(next);
    clearWorldTransform();
}

fn settleLivePan(state: *zx.State(State), next: *State, d: *Drag, el_w: f64, el_h: f64) void {
    applyWorldPan(&next.camera, d, el_w, el_h);
    clearDrag(next);
    next.camera = clampCamera(next.camera, el_w, el_h);
    publishWithClear(state, next.*);
}

fn isTouch(pe: zx.client.events.PointerEvent) bool {
    return std.mem.eql(u8, pe.pointer_type, "touch");
}

fn pinchDistance(d: Drag) f64 {
    const dx = @as(f64, @floatFromInt(d.last2_x - d.last_x));
    const dy = @as(f64, @floatFromInt(d.last2_y - d.last_y));
    return @sqrt(dx * dx + dy * dy);
}

fn midPoint(d: Drag) struct { x: f64, y: f64 } {
    return .{
        .x = @as(f64, @floatFromInt(d.last_x + d.last2_x)) * 0.5,
        .y = @as(f64, @floatFromInt(d.last_y + d.last2_y)) * 0.5,
    };
}

fn isTrackedPointer(d: Drag, pointer_id: i32) bool {
    if (pointer_id == d.pointer_id) return true;
    return d.second_active and pointer_id == d.pointer2_id;
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

fn stopBubble(e: *zx.client.Event.Stateful) void {
    e.stopPropagation();
    _ = e.state(State);
}

fn clientState(e: *zx.client.Event.Stateful) ?*zx.State(State) {
    if (!zx.platform.isClient()) return null;
    return e.state(State);
}

pub fn onWheel(e: *zx.client.Event.Stateful) void {
    e.preventDefault();
    const state = clientState(e) orelse return;
    var next = state.get();
    refreshStageCache();
    const size = stageSize();

    applyWorldPan(&next.camera, &live_drag, size.w, size.h);
    clearDrag(&next);

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

    cam_preview = .{};
    next.camera = zoomTo(base, base.z - delta * sens, focus.x, focus.y, size.w, size.h);
    next.tip.hovered = null;
    publishWithClear(state, next);
}

pub fn onPointerDown(e: *zx.client.Event.Stateful) void {
    const state = clientState(e) orelse return;
    var next = state.get();
    const pe = e.as(zx.client.events.PointerEvent, zx.allocator);
    if (!isTouch(pe) and pe.button != 0) return;

    refreshStageCache();
    flushCamPreviewNow();
    next = state.get();

    var d = activeDrag(next);
    const size = stageSize();

    if (d.active) {
        if (!d.second_active and pe.pointer_id != d.pointer_id) {
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
            publishWithClear(state, next);
        }
        return;
    }

    capturePointer(pe.pointer_id);
    d = .{
        .active = true,
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
    const state = clientState(e) orelse return;
    var next = state.get();
    var d = activeDrag(next);
    const pe = e.as(zx.client.events.PointerEvent, zx.allocator);
    const size = stageSize();
    var cam = if (cam_preview.active) cam_preview.live else clampCamera(next.camera, size.w, size.h);

    if (!d.active) {
        const focus = pointerFocus(pe.client_x, pe.client_y, size.w, size.h);
        const hovered = hitPinIndex(focus.x, focus.y, cam);
        if (next.tip.hovered == hovered) return;
        next.tip.hovered = hovered;
        state.set(next);
        return;
    }

    if (d.second_active) {
        if (!isTrackedPointer(d, pe.pointer_id)) return;

        const old = midPoint(d);
        const old_dist = d.last_pinch_dist;

        if (pe.pointer_id == d.pointer_id) {
            d.last_x = pe.client_x;
            d.last_y = pe.client_y;
        } else {
            d.last2_x = pe.client_x;
            d.last2_y = pe.client_y;
        }

        const new_dist = pinchDistance(d);
        const new_pt = midPoint(d);

        e.preventDefault();
        if (old_dist >= MIN_PINCH_DIST and new_dist >= MIN_PINCH_DIST) {
            const focus = pointerFocus(@intFromFloat(old.x), @intFromFloat(old.y), size.w, size.h);
            cam = zoomTo(cam, cam.z + std.math.log2(new_dist / old_dist), focus.x, focus.y, size.w, size.h);
        }
        cam.x -= new_pt.x - old.x;
        cam.y -= new_pt.y - old.y;
        cam = clampCamera(cam, size.w, size.h);
        d.last_pinch_dist = new_dist;
        live_drag = d;
        updateCamPreviewLive(state, clampCamera(next.camera, size.w, size.h), cam, true);
        return;
    }

    if (pe.pointer_id != d.pointer_id) return;

    if (!isTouch(pe) and (pe.buttons & 1) == 0) {
        flushCamPreviewNow();
        next = state.get();
        releasePointer(d.pointer_id);
        settleLivePan(state, &next, &d, size.w, size.h);
        return;
    }

    const adx = @abs(pe.client_x - d.start_x);
    const ady = @abs(pe.client_y - d.start_y);
    if (adx > CLICK_SLOP_PX or ady > CLICK_SLOP_PX) d.moved = true;

    if (!d.moved) {
        d.last_x = pe.client_x;
        d.last_y = pe.client_y;
        live_drag = d;
        return;
    }

    e.preventDefault();
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
        publishWithClear(state, next);
    }
}

pub fn onPointerUp(e: *zx.client.Event.Stateful) void {
    const state = clientState(e) orelse return;
    flushCamPreviewNow();
    var next = state.get();
    var d = activeDrag(next);
    if (!d.active) return;

    const pe = e.as(zx.client.events.PointerEvent, zx.allocator);
    if (!isTrackedPointer(d, pe.pointer_id)) return;

    const size = stageSize();

    if (d.second_active) {
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
    clearDrag(&next);
    publishWithClear(state, next);
}

pub fn onPointerLeave(e: *zx.client.Event.Stateful) void {
    const state = clientState(e) orelse return;
    var next = state.get();
    if (next.tip.hovered == null) return;
    next.tip.hovered = null;
    state.set(next);
}

pub fn onControlsPointer(e: *zx.client.Event.Stateful) void {
    stopBubble(e);
}

pub fn onDockWheel(e: *zx.client.Event.Stateful) void {
    stopBubble(e);
}

pub fn onTipPointer(e: *zx.client.Event.Stateful) void {
    stopBubble(e);
}

pub fn onTipClose(e: *zx.client.Event.Stateful) void {
    e.stopPropagation();
    const state = e.state(State);
    var next = state.get();
    next.tip = .{};
    state.set(next);
}

fn zoomStep(e: *zx.client.Event.Stateful, step: f64) void {
    const state = clientState(e) orelse return;
    flushCamPreviewNow();
    var next = state.get();
    refreshStageCache();
    const size = stageSize();
    applyWorldPan(&next.camera, &live_drag, size.w, size.h);
    clearDrag(&next);
    const cam = clampCamera(next.camera, size.w, size.h);
    next.camera = zoomTo(cam, cam.z + step, size.w * 0.5, size.h * 0.5, size.w, size.h);
    publishWithClear(state, next);
}

pub fn onZoomIn(e: *zx.client.Event.Stateful) void {
    zoomStep(e, ZOOM_STEP_BUTTON);
}

pub fn onZoomOut(e: *zx.client.Event.Stateful) void {
    zoomStep(e, -ZOOM_STEP_BUTTON);
}

pub fn onReset(e: *zx.client.Event.Stateful) void {
    const state = clientState(e) orelse return;
    flushCamPreviewNow();
    live_drag = .{};
    clearWorldTransform();
    refreshStageCache();
    const size = stageSize();
    state.set(.{ .camera = initialCamera(size.w, size.h) });
}

pub fn onSearchToggle(e: *zx.client.Event.Stateful) void {
    e.stopPropagation();
    const state = clientState(e) orelse return;
    var next = state.get();
    next.search.open = !next.search.open;
    if (!next.search.open) next.search.len = 0;
    if (next.search.open) next.join.open = false;
    state.set(next);
    if (next.search.open) focusElement("map-search-input");
}

pub fn onSearchInput(e: *zx.client.Event.Stateful) void {
    e.stopPropagation();
    const state = clientState(e) orelse return;
    const raw = e.value() orelse "";
    var next = state.get();
    const n = @min(raw.len, next.search.query.len);
    if (n > 0) @memcpy(next.search.query[0..n], raw[0..n]);
    next.search.len = n;
    next.search.open = true;
    state.set(next);
}

pub fn onSelectUser(e: *zx.client.Event.Stateful) void {
    e.stopPropagation();
    e.preventDefault();
    const state = clientState(e) orelse return;
    var next = state.get();
    const raw = elementAttr(e, "value") orelse e.value() orelse return;
    const user_index = std.fmt.parseInt(usize, raw, 10) catch return;
    const size = stageSize();
    focusUser(&next, user_index, size.w, size.h);
    next.search = .{};
    state.set(next);
}

fn elementAttr(e: *zx.client.Event.Stateful, comptime attr: []const u8) ?[]const u8 {
    if (comptime zx.platform.role != .client) return null;
    const event = e.getEvent();
    const current = event.ref.get(js.Object, "currentTarget") catch return null;
    defer current.deinit();
    return current.getAlloc(js.String, zx.allocator, attr) catch null;
}

fn linkIndexFromId(id: []const u8) ?usize {
    const prefixes = [_][]const u8{ "link_label_", "link_href_" };
    for (prefixes) |prefix| {
        if (std.mem.startsWith(u8, id, prefix)) {
            return std.fmt.parseInt(usize, id[prefix.len..], 10) catch null;
        }
    }
    return null;
}

pub fn fmtJoinLinkId(allocator: zx.Allocator, comptime which: enum { label, href }, index: usize) []const u8 {
    const prefix = switch (which) {
        .label => "link_label_",
        .href => "link_href_",
    };
    return std.fmt.allocPrint(allocator, "{s}{d}", .{ prefix, index }) catch "";
}

pub fn onJoinToggle(e: *zx.client.Event.Stateful) void {
    e.stopPropagation();
    const state = clientState(e) orelse return;
    var next = state.get();
    next.join.open = !next.join.open;
    if (next.join.open) {
        next.search.open = false;
        next.search.len = 0;
        next.join.err = .none;
    }
    state.set(next);
    if (next.join.open) focusElement("map-join-username");
}

pub fn onJoinMode(e: *zx.client.Event.Stateful) void {
    e.stopPropagation();
    const state = clientState(e) orelse return;
    var next = state.get();
    const raw = e.value() orelse return;
    next.join.location_mode = std.meta.stringToEnum(JoinLocationMode, raw) orelse return;
    next.join.err = .none;
    if (next.join.location_mode != .city) next.join.city_index = null;
    state.set(next);
}

pub fn onJoinDetect(e: *zx.client.Event.Stateful) void {
    e.stopPropagation();
    e.preventDefault();
    const state = clientState(e) orelse return;
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
    const state = clientState(e) orelse return;
    var next = state.get();
    if (next.join.link_count < MAX_JOIN_LINKS) next.join.link_count += 1;
    next.join.err = .none;
    state.set(next);
}

pub fn onJoinRemoveLink(e: *zx.client.Event.Stateful) void {
    e.stopPropagation();
    e.preventDefault();
    const state = clientState(e) orelse return;
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

fn setJoinLinkField(e: *zx.client.Event.Stateful, comptime which: enum { label, href }) void {
    e.stopPropagation();
    const state = clientState(e) orelse return;
    const idx = linkIndexFromId(elementAttr(e, "id") orelse return) orelse return;
    if (idx >= MAX_JOIN_LINKS) return;
    var next = state.get();
    const value = e.value() orelse "";
    switch (which) {
        .label => next.join.links[idx].label.set(value),
        .href => next.join.links[idx].href.set(value),
    }
    next.join.err = .none;
    state.set(next);
}

pub fn onJoinLinkLabel(e: *zx.client.Event.Stateful) void {
    setJoinLinkField(e, .label);
}

pub fn onJoinLinkHref(e: *zx.client.Event.Stateful) void {
    setJoinLinkField(e, .href);
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
            const loaded = cities();
            if (idx >= loaded.len) break :blk null;
            break :blk .{ .lat = loaded[idx].lat, .lng = loaded[idx].lng };
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

/// Manual JSON to avoid pulling std.json into the wasm binary.
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
    if (comptime zx.platform.role != .client) return;
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

fn setJoinError(state: *zx.State(State), next: *State, err: JoinError) void {
    next.join.err = err;
    state.set(next.*);
}

const JoinFormData = struct {
    username: []const u8,
    city: []const u8,
    lat: []const u8,
    lng: []const u8,
    link_label: []const []const u8,
    link_href: []const []const u8,
};

fn applyJoinFormData(join: *Join, data: JoinFormData) void {
    join.username.set(data.username);
    join.lat.set(data.lat);
    join.lng.set(data.lng);

    if (data.city.len == 0) {
        join.city_index = null;
    } else {
        const index = std.fmt.parseInt(usize, data.city, 10) catch null;
        join.city_index = if (index) |i| if (i < cities().len) i else null else null;
    }

    for (0..MAX_JOIN_LINKS) |i| {
        join.links[i].label.set(if (i < data.link_label.len) data.link_label[i] else "");
        join.links[i].href.set(if (i < data.link_href.len) data.link_href[i] else "");
    }
}

pub fn onJoinSubmit(action: *zx.client.Action.Stateful) void {
    const data = action.data(JoinFormData);
    const state = action.state(State);
    var next = state.get();
    applyJoinFormData(&next.join, data);
    const nick = trimAscii(next.join.username.text());
    if (!isValidNick(nick)) return setJoinError(state, &next, .username);

    const coords = resolveJoinCoords(next.join) orelse return setJoinError(state, &next, .location);

    for (next.join.links[0..next.join.link_count]) |link| {
        const label = trimAscii(link.label.text());
        const href = trimAscii(link.href.text());
        if ((label.len == 0) != (href.len == 0)) return setJoinError(state, &next, .links);
    }

    const json = buildPersonJson(zx.allocator, next.join, coords) catch return setJoinError(state, &next, .links);
    const base = sanitizeFilename(zx.allocator, nick) catch return setJoinError(state, &next, .username);
    const filename = std.fmt.allocPrint(zx.allocator, "{s}.json", .{base}) catch return setJoinError(state, &next, .username);
    openGithubNewFile(zx.allocator, filename, json) catch return setJoinError(state, &next, .links);
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

fn fmtScreenPoint(allocator: zx.Allocator, pin: Pin, cam: Camera) []const u8 {
    const p = screenPos(pin, cam);
    return std.fmt.allocPrint(allocator, "left:{d:.1}px;top:{d:.1}px", .{ p.x, p.y }) catch "";
}

pub fn fmtPinStyle(allocator: zx.Allocator, pin: Pin, cam: Camera) []const u8 {
    return fmtScreenPoint(allocator, pin, cam);
}

pub fn fmtTipStyle(allocator: zx.Allocator, pin: Pin, cam: Camera) []const u8 {
    return fmtScreenPoint(allocator, pin, cam);
}
