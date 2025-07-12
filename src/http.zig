const std = @import("std");
const testing = std.testing;
const net = std.net;

pub const Method = enum { GET, POST, PUT, DELETE };
pub const Error = error{
    InvalidRequest,
};

const defaultVersion = "HTTP/1.1";
const defaultSeparator = "\r\n";

pub const Request = struct {
    allocator: std.mem.Allocator,

    status: []const u8,

    method: Method,
    uri: []const u8,
    path_segments: []const []const u8,
    version: []const u8,

    pub fn init(allocator: std.mem.Allocator, reader: anytype) !Request {
        const status = try reader.readUntilDelimiterAlloc(allocator, '\r', 512);

        var status_iter = std.mem.splitSequence(u8, status, " ");

        const method_raw = status_iter.next() orelse return Error.InvalidRequest;
        const req_method = std.meta.stringToEnum(Method, method_raw) orelse return Error.InvalidRequest;
        const req_uri = status_iter.next() orelse return Error.InvalidRequest;
        const req_version = status_iter.next() orelse return Error.InvalidRequest;

        var req = Request{
            .allocator = allocator,
            .status = status,
            .method = req_method,
            .uri = req_uri,
            .path_segments = undefined,
            .version = req_version,
        };

        try req.parsePath();

        return req;
    }

    pub fn deinit(self: *Request) void {
        self.allocator.free(self.status);
        self.allocator.free(self.path_segments);
    }

    fn parsePath(self: *Request) !void {
        var path_segments_buf: std.ArrayList([]const u8) = .init(self.allocator);

        var path_segments_iter = std.mem.splitSequence(u8, self.uri, "/");
        while (path_segments_iter.next()) |seg| {
            if (seg.len == 0) {
                continue;
            }

            try path_segments_buf.append(seg);
        }

        self.path_segments = try path_segments_buf.toOwnedSlice();
    }
};

test Request {
    const request_raw = "GET /echo/abcd HTTP/1.1\r\nHost: localhost:4221\r\nUser-Agent: curl/7.64.1\r\nAccept: */*\r\n\r\n";
    var buf_stream = std.io.fixedBufferStream(request_raw);
    const reader = buf_stream.reader();
    var req = try Request.init(testing.allocator, reader);
    defer req.deinit();

    try testing.expectEqual(Method.GET, req.method);
    try testing.expectEqualStrings("/echo/abcd", req.uri);
    try testing.expectEqualStrings("HTTP/1.1", req.version);
    try testing.expectEqualStrings("echo", req.path_segments[0]);
    try testing.expectEqualStrings("abcd", req.path_segments[1]);
}

pub const StatusCode = enum {
    ok,
    not_found,

    fn getCode(self: StatusCode) u16 {
        return switch (self) {
            .ok => 200,
            .not_found => 404,
        };
    }

    inline fn getCodeString(self: StatusCode) []const u8 {
        var buf = [_]u8{ 0, 0, 0 };
        return std.fmt.bufPrintIntToSlice(buf[0..3], self.getCode(), 10, std.fmt.Case.lower, .{});
    }

    fn getMessage(self: StatusCode) []const u8 {
        return switch (self) {
            .ok => "OK",
            .not_found => "Not Found",
        };
    }
};

test StatusCode {
    try testing.expectEqual(200, StatusCode.ok.getCode());
    try testing.expectEqualStrings("Not Found", StatusCode.not_found.getMessage());
    try testing.expectEqualStrings("404", StatusCode.not_found.getCodeString());
}

pub const Response = struct {
    allocator: std.mem.Allocator,
    headers: std.StringHashMap([]const u8),
    body: ?[]u8,

    pub fn init(allocator: std.mem.Allocator) Response {
        return .{
            .allocator = allocator,
            .headers = std.StringHashMap([]const u8).init(allocator),
            .body = null,
        };
    }

    pub fn deinit(self: *Response) void {
        var iter = self.headers.iterator();
        while (iter.next()) |kv| {
            self.allocator.free(kv.value_ptr.*);
        }

        self.headers.deinit();
        self.allocator.free(self.body.?);
    }

    pub fn setHeader(self: *Response, key: []const u8, val: []const u8) !void {
        const val_new = try self.allocator.alloc(u8, val.len);
        @memcpy(val_new, val);
        try self.headers.put(key, val_new);
    }

    pub fn setBody(self: *Response, body: []const u8) !void {
        try self.headers.put(
            "Content-Length",
            try std.fmt.allocPrint(self.allocator, "{d}", .{body.len}),
        );
        self.body = try self.allocator.alloc(u8, body.len);
        @memcpy(self.body.?, body);
    }

    pub fn send(self: *Response, code: StatusCode, writer: anytype) !void {
        var buffer: std.ArrayList(u8) = .init(self.allocator);
        defer buffer.deinit();

        // Status line
        _ = try buffer.appendSlice(defaultVersion);
        _ = try buffer.append(' ');
        _ = try buffer.appendSlice(code.getCodeString());
        _ = try buffer.append(' ');
        _ = try buffer.appendSlice(code.getMessage());
        _ = try buffer.appendSlice(defaultSeparator);

        // Headers
        var headers_iter = self.headers.iterator();
        while (headers_iter.next()) |entry| {
            _ = try buffer.appendSlice(entry.key_ptr.*);
            _ = try buffer.appendSlice(": ");
            _ = try buffer.appendSlice(entry.value_ptr.*);
            _ = try buffer.appendSlice(defaultSeparator);
        }

        _ = try buffer.appendSlice(defaultSeparator);
        if (self.body != null) {
            _ = try buffer.appendSlice(self.body.?);
        }

        _ = try writer.write(buffer.items);
    }
};

test Response {
    var resp = Response.init(testing.allocator);
    defer resp.deinit();

    try resp.setHeader("X-Test-Header", "foobar");
    try resp.setBody("hello world!");

    var buffer = std.ArrayList(u8).init(testing.allocator);
    defer buffer.deinit();

    try resp.send(StatusCode.ok, buffer.writer());
    try testing.expectEqualStrings("HTTP/1.1 200 OK\r\nX-Test-Header: foobar\r\nContent-Length: 12\r\n\r\nhello world!", buffer.items);
}

pub const Server = struct {
    address: net.Address,
    listener: net.Server,

    pub fn init(host: []const u8, port: u16) !Server {
        const address = try net.Address.resolveIp(host, port);

        return .{
            .address = address,
            .listener = try address.listen(.{ .reuse_address = true }),
        };
    }

    pub fn serveRequest(self: *Server, allocator: std.mem.Allocator) !void {
        const conn = try self.listener.accept();
        defer conn.stream.close();

        var arena_alloc = std.heap.ArenaAllocator.init(allocator);
        defer arena_alloc.deinit();

        const alloc = arena_alloc.allocator();

        var req = try Request.init(alloc, conn.stream.reader());
        defer req.deinit();

        if (std.mem.eql(u8, req.uri, "/")) {
            var resp = Response.init(alloc);
            try resp.send(StatusCode.ok, conn.stream.writer());
            return;
        }

        if (req.path_segments.len > 0 and std.mem.eql(u8, req.path_segments[0], "echo")) {
            var resp = Response.init(alloc);
            if (req.path_segments.len > 1) {
                try resp.setHeader("Content-Type", "text/plain");
                try resp.setBody(req.path_segments[1]);
            }

            try resp.send(StatusCode.ok, conn.stream.writer());
        }

        var resp = Response.init(alloc);
        try resp.send(StatusCode.not_found, conn.stream.writer());
    }

    pub fn deinit(self: *Server) void {
        self.listener.deinit();
    }
};
