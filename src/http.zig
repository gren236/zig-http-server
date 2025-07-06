const std = @import("std");
const testing = std.testing;
const net = std.net;

pub const Method = enum { GET, POST, PUT, DELETE };
pub const Error = error{
    InvalidRequest,
};

pub const Request = struct {
    allocator: std.mem.Allocator,

    status: []const u8,

    method: Method,
    uri: []const u8,
    version: []const u8,

    pub fn init(allocator: std.mem.Allocator, reader: anytype) !Request {
        const status = try reader.readUntilDelimiterAlloc(allocator, '\r', 512);

        var status_iter = std.mem.splitSequence(u8, status, " ");

        const method_raw = status_iter.next() orelse return Error.InvalidRequest;
        const req_method = std.meta.stringToEnum(Method, method_raw) orelse return Error.InvalidRequest;
        const req_uri = status_iter.next() orelse return Error.InvalidRequest;
        const req_version = status_iter.next() orelse return Error.InvalidRequest;

        return .{
            .allocator = allocator,
            .status = status,
            .method = req_method,
            .uri = req_uri,
            .version = req_version,
        };
    }

    pub fn deinit(self: *Request) void {
        self.allocator.free(self.status);
    }
};

test Request {
    const request_raw = "GET /index.html HTTP/1.1\r\nHost: localhost:4221\r\nUser-Agent: curl/7.64.1\r\nAccept: */*\r\n\r\n";
    var buf_stream = std.io.fixedBufferStream(request_raw);
    const reader = buf_stream.reader();
    var req = try Request.init(testing.allocator, reader);
    defer req.deinit();

    try testing.expectEqual(Method.GET, req.method);
    try testing.expectEqualStrings("/index.html", req.uri);
    try testing.expectEqualStrings("HTTP/1.1", req.version);
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

        var req = try Request.init(arena_alloc.allocator(), conn.stream.reader());
        defer req.deinit();

        _ = try conn.stream.write("HTTP/1.1 ");
        if (std.mem.eql(u8, req.uri, "/")) {
            _ = try conn.stream.write("200 OK");
        } else {
            _ = try conn.stream.write("404 Not Found");
        }
        _ = try conn.stream.write("\r\n\r\n");
    }

    pub fn deinit(self: *Server) void {
        self.listener.deinit();
    }
};
