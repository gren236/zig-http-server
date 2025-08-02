const std = @import("std");
const testing = std.testing;
const net = std.net;

pub const Method = enum { GET, POST, PUT, DELETE };
pub const Error = error{
    InvalidRequest,
};

const defaultVersion = "HTTP/1.1";
const defaultSeparator = "\r\n";

pub fn readUntilSequenceOrEofAlloc(allocator: std.mem.Allocator, reader: anytype, seq: []const u8, max_size: usize) ![]u8 {
    var array_list = std.ArrayList(u8).init(allocator);
    defer array_list.deinit();

    if (seq.len == 0) {
        try reader.readAllArrayList(&array_list, max_size);
    }

    var seq_i: usize = 0;
    var in_seq = false;
    var bytes_read: usize = 0;
    while (true) {
        if (bytes_read > max_size) return error.StreamTooLong;

        const byte = reader.readByte() catch |err| switch (err) {
            error.EndOfStream => if (array_list.items.len == 0) {
                return array_list.toOwnedSlice();
            } else if (in_seq) {
                try array_list.appendSlice(seq[0..seq_i]);
                return array_list.toOwnedSlice();
            } else {
                return array_list.toOwnedSlice();
            },
            else => |e| return e,
        };

        bytes_read += 1;

        if (!in_seq and byte == seq[0]) {
            seq_i = 1;
            in_seq = true;
            continue;
        }

        if (in_seq) {
            // we are in the sequence and try to match the byte
            if (byte == seq[seq_i]) {
                seq_i += 1;

                // if we matched the sequence fully - break the loop
                if (seq_i == seq.len) break;

                continue;
            }

            // byte is not the same, so that's not our sequence
            try array_list.appendSlice(seq[0..seq_i]);
            in_seq = false;
        }

        try array_list.append(byte);
    }

    return try array_list.toOwnedSlice();
}

test readUntilSequenceOrEofAlloc {
    var buffer1 = std.io.fixedBufferStream("hello world foo bar xyz");
    const result1 = try readUntilSequenceOrEofAlloc(testing.allocator, buffer1.reader(), "xyz", 64);
    defer testing.allocator.free(result1);
    try testing.expectEqualStrings("hello world foo bar ", result1);

    var buffer2 = std.io.fixedBufferStream("hello worldx foo barxyz");
    const result2 = try readUntilSequenceOrEofAlloc(testing.allocator, buffer2.reader(), "xyz", 64);
    defer testing.allocator.free(result2);
    try testing.expectEqualStrings("hello worldx foo bar", result2);

    var buffer3 = std.io.fixedBufferStream("hello world\r foo bar\r\n");
    const result3 = try readUntilSequenceOrEofAlloc(testing.allocator, buffer3.reader(), "\r\n", 64);
    defer testing.allocator.free(result3);
    try testing.expectEqualStrings("hello world\r foo bar", result3);

    var buffer4 = std.io.fixedBufferStream("hello world\r\n foo bar\r\n\r\n");
    const result4 = try readUntilSequenceOrEofAlloc(testing.allocator, buffer4.reader(), "\r\n\r\n", 64);
    defer testing.allocator.free(result4);
    try testing.expectEqualStrings("hello world\r\n foo bar", result4);

    var buffer5 = std.io.fixedBufferStream("hello world\r\n foo bar");
    const result5 = try readUntilSequenceOrEofAlloc(testing.allocator, buffer5.reader(), "\r\n\r\n", 64);
    defer testing.allocator.free(result5);
    try testing.expectEqualStrings("hello world\r\n foo bar", result5);

    var buffer6 = std.io.fixedBufferStream("hello world\r\n foo bar\r");
    const result6 = try readUntilSequenceOrEofAlloc(testing.allocator, buffer6.reader(), "\r\n\r\n", 64);
    defer testing.allocator.free(result6);
    try testing.expectEqualStrings("hello world\r\n foo bar\r", result6);

    var buffer7 = std.io.fixedBufferStream("");
    const result7 = try readUntilSequenceOrEofAlloc(testing.allocator, buffer7.reader(), "\r\n\r\n", 64);
    defer testing.allocator.free(result7);
    try testing.expectEqualStrings("", result7);
    try testing.expectEqual(0, result7.len);
}

const header_names = blk: {
    const fields = std.meta.fields(Header);
    var res: [fields.len][]const u8 = undefined;

    for (fields, 0..) |field, i| {
        var buffer: [field.name.len]u8 = undefined;

        var in_word = false;
        var j: usize = 0;
        for (field.name) |c| {
            switch (c) {
                'A'...'Z', 'a'...'z' => if (!in_word) {
                    in_word = true;
                    buffer[j] = std.ascii.toUpper(c);
                } else {
                    buffer[j] = c;
                },
                '_' => {
                    in_word = false;
                    buffer[j] = '-';
                },
                else => {
                    in_word = false;
                    buffer[j] = c;
                },
            }
            j += 1;
        }

        res[i] = std.fmt.comptimePrint("{s}", .{buffer});
    }

    break :blk res;
};

const header_names_map = std.StaticStringMap(Header).initComptime(blk: {
    var res: [header_names.len]struct { []const u8, Header } = undefined;

    for (header_names, 0..) |header_name, i| {
        var name_lower: [header_name.len]u8 = undefined;
        _ = std.ascii.lowerString(&name_lower, header_name);
        const final = name_lower;
        res[i] = .{ &final, @enumFromInt(i) };
    }

    break :blk res;
});

pub const Header = enum {
    content_length,
    content_type,
    user_agent,
    host,
    accept,
    accept_encoding,

    pub inline fn toString(self: Header) []const u8 {
        return header_names[@intFromEnum(self)];
    }

    pub fn fromString(buffer: []u8, s: []const u8) ?Header {
        return header_names_map.get(std.ascii.lowerString(buffer, s));
    }
};

test Header {
    const res = Header.user_agent.toString();
    try testing.expectEqualStrings("User-Agent", res);

    const buffer = try testing.allocator.alloc(u8, 12);
    defer testing.allocator.free(buffer);

    try testing.expectEqual(Header.fromString(buffer, "Content-Type").?, Header.content_type);
}

const PathSegments = []const []const u8;

fn parsePathIntoSegments(allocator: std.mem.Allocator, path: []const u8) !PathSegments {
    var path_segments_buf: std.ArrayList([]const u8) = .init(allocator);

    var path_segments_iter = std.mem.splitSequence(u8, path, "/");
    while (path_segments_iter.next()) |seg| {
        if (seg.len == 0) {
            continue;
        }

        try path_segments_buf.append(seg);
    }

    return try path_segments_buf.toOwnedSlice();
}

fn matchSegmentsWithWildcard(actual: PathSegments, pattern: PathSegments) bool {
    if (actual.len != pattern.len) return false;

    for (actual, pattern) |actual_seg, pattern_seg| {
        if (!std.mem.eql(u8, actual_seg, pattern_seg)) {
            if (!std.mem.eql(u8, pattern_seg, "*")) return false;
        }
    }

    return true;
}

pub const Request = struct {
    allocator: std.mem.Allocator,

    status_raw: []const u8 = undefined,
    headers_raw: ?[]const u8 = null,

    version: []const u8 = undefined,
    method: Method = undefined,
    uri: []const u8 = undefined,
    path_segments: PathSegments = undefined,
    headers: std.AutoHashMap(Header, []const u8),
    body: ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator, reader: anytype) !Request {
        var req = Request{
            .allocator = allocator,
            .headers = std.AutoHashMap(Header, []const u8).init(allocator),
        };

        req.status_raw = try readUntilSequenceOrEofAlloc(allocator, reader, defaultSeparator, 1024);
        try req.parseStatus();
        req.path_segments = try parsePathIntoSegments(allocator, req.uri);

        const headers_raw = try readUntilSequenceOrEofAlloc(allocator, reader, defaultSeparator ** 2, 1024);
        if (headers_raw.len != 0) {
            req.headers_raw = headers_raw;
            try req.parseHeaders();
        }

        if (req.headers.contains(Header.content_length)) {
            const content_length = req.headers.get(Header.content_length) orelse return Error.InvalidRequest;
            const len = try std.fmt.parseInt(usize, content_length, 10);

            const buffer = try allocator.alloc(u8, len);
            _ = try reader.readAll(buffer);

            req.body = buffer;
        }

        return req;
    }

    pub fn deinit(self: *Request) void {
        self.allocator.free(self.status_raw);
        if (self.headers_raw != null) {
            self.allocator.free(self.headers_raw.?);
        }
        if (self.body != null) {
            self.allocator.free(self.body.?);
        }
        self.headers.deinit();
        self.allocator.free(self.path_segments);
    }

    fn parseStatus(self: *Request) !void {
        var status_iter = std.mem.splitSequence(u8, self.status_raw, " ");

        const method_raw = status_iter.next() orelse return Error.InvalidRequest;
        self.method = std.meta.stringToEnum(Method, method_raw) orelse return Error.InvalidRequest;
        self.uri = status_iter.next() orelse return Error.InvalidRequest;
        self.version = status_iter.next() orelse return Error.InvalidRequest;
    }

    fn parseHeaders(self: *Request) !void {
        if (self.headers_raw == null) return;

        var headers_iter = std.mem.splitSequence(u8, self.headers_raw.?, defaultSeparator);
        while (headers_iter.next()) |header_raw| {
            var header_raw_iter = std.mem.splitSequence(u8, header_raw, ":");
            const name = header_raw_iter.next() orelse return Error.InvalidRequest;
            const value = header_raw_iter.rest();

            const buffer = try self.allocator.alloc(u8, name.len);
            defer self.allocator.free(buffer);

            const header_name = Header.fromString(buffer, name) orelse return Error.InvalidRequest;

            try self.headers.put(header_name, std.mem.trim(u8, value, " "));
        }
    }
};

test Request {
    const request_raw =
        "GET /echo/abcd HTTP/1.1\r\nHost: localhost:4221\r\nUser-Agent: curl/7.64.1\r\nContent-Type: application/octet-stream\r\nContent-Length: 5\r\nAccept: */*\r\n\r\n12345";
    var buf_stream = std.io.fixedBufferStream(request_raw);
    const reader = buf_stream.reader();
    var req = try Request.init(testing.allocator, reader);
    defer req.deinit();

    try testing.expectEqual(Method.GET, req.method);
    try testing.expectEqualStrings("/echo/abcd", req.uri);
    try testing.expectEqualStrings("HTTP/1.1", req.version);
    try testing.expectEqualStrings("echo", req.path_segments[0]);
    try testing.expectEqualStrings("abcd", req.path_segments[1]);
    try testing.expectEqual(Header.user_agent, req.headers.getKey(Header.user_agent).?);
    try testing.expectEqualStrings("localhost:4221", req.headers.get(Header.host).?);
    try testing.expectEqualStrings("12345", req.body.?);
}

pub const StatusCode = enum {
    ok,
    created,
    bad_request,
    not_found,
    internal_error,

    fn getCode(self: StatusCode) u16 {
        return switch (self) {
            .ok => 200,
            .created => 201,
            .bad_request => 400,
            .not_found => 404,
            .internal_error => 500,
        };
    }

    inline fn getCodeString(self: StatusCode) []const u8 {
        var buf = [_]u8{ 0, 0, 0 };
        return std.fmt.bufPrintIntToSlice(buf[0..3], self.getCode(), 10, std.fmt.Case.lower, .{});
    }

    fn getMessage(self: StatusCode) []const u8 {
        return switch (self) {
            .ok => "OK",
            .created => "Created",
            .bad_request => "Bad Request",
            .not_found => "Not Found",
            .internal_error => "Internal Server Error",
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
    headers: std.AutoHashMap(Header, []const u8),
    body: ?[]u8,

    pub fn init(allocator: std.mem.Allocator) Response {
        return .{
            .allocator = allocator,
            .headers = std.AutoHashMap(Header, []const u8).init(allocator),
            .body = null,
        };
    }

    pub fn deinit(self: *Response) void {
        var iter = self.headers.iterator();
        while (iter.next()) |kv| {
            self.allocator.free(kv.value_ptr.*);
        }

        self.headers.deinit();

        if (self.body != null) {
            self.allocator.free(self.body.?);
        }
    }

    pub fn setHeader(self: *Response, header: Header, val: []const u8) !void {
        const val_new = try self.allocator.alloc(u8, val.len);
        @memcpy(val_new, val);
        try self.headers.put(header, val_new);
    }

    pub fn setBody(self: *Response, body: []const u8) !void {
        try self.headers.put(
            Header.content_length,
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
            _ = try buffer.appendSlice(entry.key_ptr.*.toString());
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

    try resp.setHeader(Header.user_agent, "foobar");
    try resp.setBody("hello world!");

    var buffer = std.ArrayList(u8).init(testing.allocator);
    defer buffer.deinit();

    try resp.send(StatusCode.ok, buffer.writer());
    try testing.expectEqualStrings("HTTP/1.1 200 OK\r\nUser-Agent: foobar\r\nContent-Length: 12\r\n\r\nhello world!", buffer.items);
}

pub const Route = struct { method: Method, uri: []const u8, handler: Handler };

// Interface for any generic handler implementation
pub const Handler = struct {
    ptr: *anyopaque,
    handleFn: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator, req: *Request, resp: *Response) anyerror!StatusCode,

    pub fn handle(self: Handler, allocator: std.mem.Allocator, req: *Request, resp: *Response) anyerror!StatusCode {
        return self.handleFn(self.ptr, allocator, req, resp);
    }
};

pub const Server = struct {
    allocator: std.mem.Allocator,
    address: net.Address,
    listener: net.Server,
    thread_pool: *std.Thread.Pool,
    routes: []const Route,

    pub fn init(allocator: std.mem.Allocator, host: []const u8, port: u16, routes: []const Route) !Server {
        const address = try net.Address.resolveIp(host, port);

        const thread_pool = try allocator.create(std.Thread.Pool);
        try thread_pool.init(.{ .allocator = allocator });

        return .{
            .allocator = allocator,
            .address = address,
            .listener = try address.listen(.{ .reuse_address = true }),
            .thread_pool = thread_pool,
            .routes = routes,
        };
    }

    pub fn serve(self: *Server) !void {
        while (true) {
            const conn = try self.listener.accept();

            try self.thread_pool.spawn(handleRequestThreaded, .{ self, conn });
        }
    }

    fn matchHandler(self: *Server, method: Method, uri_segments: PathSegments) ?Handler {
        for (self.routes) |route| {
            if (route.method == method) {
                const route_segments = parsePathIntoSegments(self.allocator, route.uri) catch return null;
                defer self.allocator.free(route_segments);

                if (matchSegmentsWithWildcard(uri_segments, route_segments)) return route.handler;
            }
        }

        return null;
    }

    fn handleRequestThreaded(self: *Server, conn: std.net.Server.Connection) void {
        handleRequest(self, conn) catch |err| {
            std.log.debug("Request handling failed: {}", .{err});
        };
    }

    fn handleRequest(self: *Server, conn: std.net.Server.Connection) !void {
        defer conn.stream.close();

        var arena_alloc = std.heap.ArenaAllocator.init(self.allocator);
        defer arena_alloc.deinit();

        const alloc = arena_alloc.allocator();

        var req = try Request.init(alloc, conn.stream.reader());
        defer req.deinit();

        std.log.debug("Received request: {s} {s}", .{ @tagName(req.method), req.uri });

        var resp = Response.init(alloc);
        defer resp.deinit();

        const handler = self.matchHandler(req.method, req.path_segments) orelse {
            try resp.send(StatusCode.not_found, conn.stream.writer());
            return;
        };

        const resp_code = handler.handle(self.allocator, &req, &resp) catch |err| switch (err) {
            Error.InvalidRequest => {
                std.log.err("Request malformed", .{});
                try resp.send(StatusCode.bad_request, conn.stream.writer());
                return;
            },
            else => {
                std.log.err("Request handling failed: {}", .{err});
                try resp.send(StatusCode.internal_error, conn.stream.writer());
                return;
            },
        };

        try resp.send(resp_code, conn.stream.writer());
    }

    pub fn deinit(self: *Server) void {
        self.thread_pool.deinit();
        self.allocator.destroy(self.thread_pool);
        self.listener.deinit();
    }
};
