const std = @import("std");
const config = @import("config.zig");
const http = @import("http.zig");
const handlers = @import("handlers.zig");

const AppConfig = struct {
    host: []const u8 = "127.0.0.1",
    port: u16 = 4221,
    directory: []const u8 = "",
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

    var files = handlers.Files{ .directory = conf.vals.directory };
    var user_agent = handlers.UserAgent{};
    var echo = handlers.Echo{};
    var root = handlers.Root{};

    const routes = &[_]http.Route{
        .{ .method = http.Method.GET, .uri = "/files/*", .handler = files.handler() },
        .{ .method = http.Method.GET, .uri = "/user-agent", .handler = user_agent.handler() },
        .{ .method = http.Method.GET, .uri = "/echo/*", .handler = echo.handler() },
        .{ .method = http.Method.GET, .uri = "/", .handler = root.handler() },
    };

    std.log.debug("file dir: {s}", .{conf.vals.directory});

    var server = try http.Server.init(debug_alloc.allocator(), conf.vals.host, conf.vals.port, routes);
    defer server.deinit();

    std.log.debug("Running HTTP server on {s}:{d}", .{ conf.vals.host, conf.vals.port });

    try server.serve();
}
