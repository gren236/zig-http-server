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

pub const Request = struct {
    allocator: std.mem.Allocator,

    status_raw: []const u8,
    headers_raw: ?[]const u8,

    version: []const u8,
    method: Method,
    uri: []const u8,
    path_segments: []const []const u8,
    headers: std.AutoHashMap(Header, []const u8),

    pub fn init(allocator: std.mem.Allocator, reader: anytype) !Request {
        var req = Request{
            .allocator = allocator,
            .status_raw = undefined,
            .headers_raw = null,
            .headers = std.AutoHashMap(Header, []const u8).init(allocator),
            .method = undefined,
            .uri = undefined,
            .path_segments = undefined,
            .version = undefined,
        };

        req.status_raw = try readUntilSequenceOrEofAlloc(allocator, reader, defaultSeparator, 1024);
        try req.parseStatus();
        try req.parsePath();

        const headers_raw = try readUntilSequenceOrEofAlloc(allocator, reader, defaultSeparator ** 2, 1024);
        if (headers_raw.len != 0) {
            req.headers_raw = headers_raw;
            try req.parseHeaders();
        }

        return req;
    }

    pub fn deinit(self: *Request) void {
        self.allocator.free(self.status_raw);
        if (self.headers_raw != null) {
            self.allocator.free(self.headers_raw.?);
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
    try testing.expectEqual(Header.user_agent, req.headers.getKey(Header.user_agent).?);
    try testing.expectEqualStrings("localhost:4221", req.headers.get(Header.host).?);
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

pub const Server = struct {
    allocator: std.mem.Allocator,
    address: net.Address,
    listener: net.Server,
    thread_pool: *std.Thread.Pool,

    pub fn init(allocator: std.mem.Allocator, host: []const u8, port: u16) !Server {
        const address = try net.Address.resolveIp(host, port);

        const thread_pool = try allocator.create(std.Thread.Pool);
        try thread_pool.init(.{ .allocator = allocator });

        const server = Server{
            .allocator = allocator,
            .address = address,
            .listener = try address.listen(.{ .reuse_address = true }),
            .thread_pool = thread_pool,
        };

        return server;
    }

    pub fn serve(self: *Server) !void {
        while (true) {
            const conn = try self.listener.accept();

            try self.thread_pool.spawn(Server.handleRequestThreaded, .{ self.allocator, conn });
        }
    }

    fn handleRequestThreaded(allocator: std.mem.Allocator, conn: std.net.Server.Connection) void {
        handleRequest(allocator, conn) catch |err| {
            std.log.debug("Request handling failed: {}", .{err});
        };
    }

    fn handleRequest(allocator: std.mem.Allocator, conn: std.net.Server.Connection) !void {
        defer conn.stream.close();

        var arena_alloc = std.heap.ArenaAllocator.init(allocator);
        defer arena_alloc.deinit();

        const alloc = arena_alloc.allocator();

        var req = try Request.init(alloc, conn.stream.reader());
        defer req.deinit();

        std.log.debug("Received request: {s} {s}", .{ @tagName(req.method), req.uri });

        var resp = Response.init(alloc);
        defer resp.deinit();

        if (std.mem.eql(u8, req.uri, "/")) {
            try resp.send(StatusCode.ok, conn.stream.writer());
            return;
        }

        if (std.mem.eql(u8, req.uri, "/user-agent")) {
            try resp.setHeader(Header.content_type, "text/plain");
            try resp.setBody(req.headers.get(Header.user_agent) orelse return Error.InvalidRequest);

            try resp.send(StatusCode.ok, conn.stream.writer());
            return;
        }

        if (req.path_segments.len > 0 and std.mem.eql(u8, req.path_segments[0], "echo")) {
            if (req.path_segments.len > 1) {
                try resp.setHeader(Header.content_type, "text/plain");
                try resp.setBody(req.path_segments[1]);
            }

            try resp.send(StatusCode.ok, conn.stream.writer());
            return;
        }

        try resp.send(StatusCode.not_found, conn.stream.writer());
    }

    pub fn deinit(self: *Server) void {
        self.thread_pool.deinit();
        self.allocator.destroy(self.thread_pool);
        self.listener.deinit();
    }
};
