const std = @import("std");
const net = std.net;

pub fn main() !void {
    const address = try net.Address.resolveIp("127.0.0.1", 4221);
    var listener = try address.listen(.{
        .reuse_address = true,
    });
    defer listener.deinit();

    const conn = try listener.accept();
    defer conn.stream.close();

    _ = try conn.stream.write("HTTP/1.1 200 OK\r\n\r\n");
}
