pub const Link = struct {
    label: []const u8,
    href: []const u8,
};

pub const Place = struct {
    lat: f64,
    lng: f64,
    city: []const u8 = "",
};

pub const Mascot = enum { zero, carmen, ziggy };

pub const Avatar = struct {
    mascot: Mascot,
};

pub const User = struct {
    username: []const u8,
    places: []const Place,
    links: []const Link = &.{},
    avatar: ?Avatar = null,
};

pub const Event = struct {
    name: []const u8,
    places: []const Place,
    links: []const Link = &.{},
};

pub const Mirror = struct {
    name: []const u8,
    places: []const Place,
    links: []const Link = &.{},
};

pub const LocationKind = enum { user, event, mirror };

pub const Location = union(LocationKind) {
    user: User,
    event: Event,
    mirror: Mirror,

    pub fn name(self: Location) []const u8 {
        return switch (self) {
            .user => |u| u.username,
            .event => |e| e.name,
            .mirror => |m| m.name,
        };
    }

    pub fn places(self: Location) []const Place {
        return switch (self) {
            .user => |u| u.places,
            .event => |e| e.places,
            .mirror => |m| m.places,
        };
    }

    pub fn links(self: Location) []const Link {
        return switch (self) {
            .user => |u| u.links,
            .event => |e| e.links,
            .mirror => |m| m.links,
        };
    }

    pub fn mascot(self: Location) ?Mascot {
        return switch (self) {
            .user => |u| if (u.avatar) |a| a.mascot else null,
            .event, .mirror => null,
        };
    }

    pub fn kind(self: Location) LocationKind {
        const std = @import("std");
        return std.meta.activeTag(self);
    }
};
