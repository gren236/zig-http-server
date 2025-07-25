const std = @import("std");
const http = @import("http.zig");

const host = "127.0.0.1";
const port = 4221;

fn handleRoot(req: *http.Request, resp: *http.Response) anyerror!http.StatusCode {
    _ = req;
    _ = resp;

    return http.StatusCode.ok;
}

fn handleUserAgent(req: *http.Request, resp: *http.Response) anyerror!http.StatusCode {
    try resp.setHeader(http.Header.content_type, "text/plain");
    try resp.setBody(req.headers.get(http.Header.user_agent) orelse return http.Error.InvalidRequest);

    return http.StatusCode.ok;
}

fn handleEcho(req: *http.Request, resp: *http.Response) anyerror!http.StatusCode {
    if (req.path_segments.len > 1) {
        try resp.setHeader(http.Header.content_type, "text/plain");
        try resp.setBody(req.path_segments[1]);
    }

    return http.StatusCode.ok;
}

pub fn main() !void {
    var debug_alloc: std.heap.DebugAllocator(.{}) = .init;
    defer _ = switch (debug_alloc.deinit()) {
        .leak => @panic("memory leak!"),
        .ok => void,
    };

    const handlers = &[_]http.Handler{
        .{ .method = http.Method.GET, .uri = "/user-agent", .handler_func = handleUserAgent },
        .{ .method = http.Method.GET, .uri = "/echo", .handler_func = handleEcho },
        .{ .method = http.Method.GET, .uri = "/", .handler_func = handleRoot },
    };

    var server = try http.Server(handlers).init(debug_alloc.allocator(), host, port);
    defer server.deinit();

    std.log.debug("Running HTTP server on {s}:{d}", .{ host, port });

    try server.serve();
}
