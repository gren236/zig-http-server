const std = @import("std");
const http = @import("http.zig");

const host = "127.0.0.1";
const port = 4221;

pub fn main() !void {
    var debug_alloc: std.heap.DebugAllocator(.{}) = .init;
    defer _ = switch (debug_alloc.deinit()) {
        .leak => @panic("memory leak!"),
        .ok => void,
    };

    var server = try http.Server.init(debug_alloc.allocator(), host, port);
    defer server.deinit();

    std.log.debug("Running HTTP server on {s}:{d}", .{ host, port });

    try server.serve();
}
