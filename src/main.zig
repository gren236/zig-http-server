const std = @import("std");
const http = @import("http.zig");

pub fn main() !void {
    var server = try http.Server.init("127.0.0.1", 4221);
    defer server.deinit();

    var debug_alloc: std.heap.DebugAllocator(.{}) = .init;
    defer _ = switch (debug_alloc.deinit()) {
        .leak => @panic("memory leak!"),
        .ok => void,
    };

    try server.serveRequest(debug_alloc.allocator());
}
