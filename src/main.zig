const std = @import("std");
const config = @import("config.zig");
const http = @import("http.zig");
const handlers = @import("handlers.zig");

const routes = &[_]http.Route{
    .{ .method = http.Method.GET, .uri = "/user-agent", .handler = handlers.userAgent },
    .{ .method = http.Method.GET, .uri = "/echo", .handler = handlers.echo },
    .{ .method = http.Method.GET, .uri = "/", .handler = handlers.root },
};

const AppConfig = struct {
    host: []const u8 = "127.0.0.1",
    port: u16 = 4221,
    dir: []const u8 = "",
};

pub fn main() !void {
    var debug_alloc: std.heap.DebugAllocator(.{}) = .init;
    defer _ = switch (debug_alloc.deinit()) {
        .leak => @panic("memory leak!"),
        .ok => void,
    };

    var conf = config.Config(AppConfig).init(debug_alloc.allocator());
    defer conf.deinit();

    try conf.parseFlags();

    std.log.debug("file dir: {s}", .{conf.vals.dir});

    var server = try http.Server(routes).init(debug_alloc.allocator(), conf.vals.host, conf.vals.port);
    defer server.deinit();

    std.log.debug("Running HTTP server on {s}:{d}", .{ conf.vals.host, conf.vals.port });

    try server.serve();
}
