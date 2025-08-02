const std = @import("std");
const http = @import("http.zig");

pub const Root = struct {
    fn handle(ptr: *anyopaque, allocator: std.mem.Allocator, req: *http.Request, resp: *http.Response) anyerror!http.StatusCode {
        _ = ptr;
        _ = req;
        _ = resp;
        _ = allocator;

        return http.StatusCode.ok;
    }

    pub fn handler(self: *Root) http.Handler {
        return .{
            .ptr = self,
            .handleFn = handle,
        };
    }
};

pub const UserAgent = struct {
    fn handle(ptr: *anyopaque, allocator: std.mem.Allocator, req: *http.Request, resp: *http.Response) anyerror!http.StatusCode {
        _ = ptr;
        _ = allocator;

        try resp.setHeader(http.Header.content_type, "text/plain");
        try resp.setBody(req.headers.get(http.Header.user_agent) orelse return http.Error.InvalidRequest);

        return http.StatusCode.ok;
    }

    pub fn handler(self: *UserAgent) http.Handler {
        return .{
            .ptr = self,
            .handleFn = handle,
        };
    }
};

pub const Echo = struct {
    fn handle(ptr: *anyopaque, allocator: std.mem.Allocator, req: *http.Request, resp: *http.Response) anyerror!http.StatusCode {
        _ = ptr;
        _ = allocator;

        if (req.path_segments.len >= 1) {
            try resp.setHeader(http.Header.content_type, "text/plain");
            try resp.setBody(req.path_segments[1]);
        }

        return http.StatusCode.ok;
    }

    pub fn handler(self: *Echo) http.Handler {
        return .{
            .ptr = self,
            .handleFn = handle,
        };
    }
};

pub const GetFiles = struct {
    directory: []const u8,

    fn handle(ptr: *anyopaque, allocator: std.mem.Allocator, req: *http.Request, resp: *http.Response) anyerror!http.StatusCode {
        const self: *GetFiles = @ptrCast(@alignCast(ptr));

        if (req.path_segments.len < 1) {
            return http.StatusCode.bad_request;
        }

        const filename = req.path_segments[1];

        var dir = try std.fs.openDirAbsolute(self.directory, .{});
        defer dir.close();

        const file_contents = dir.readFileAlloc(allocator, filename, 1024 * 10) catch |err| switch (err) {
            std.fs.File.OpenError.FileNotFound => return http.StatusCode.not_found,
            else => return err,
        };
        defer allocator.free(file_contents);

        try resp.setHeader(http.Header.content_type, "application/octet-stream");
        try resp.setBody(file_contents);

        return http.StatusCode.ok;
    }

    pub fn handler(self: *GetFiles) http.Handler {
        return .{
            .ptr = self,
            .handleFn = handle,
        };
    }
};

pub const PostFiles = struct {
    directory: []const u8,

    fn handle(ptr: *anyopaque, allocator: std.mem.Allocator, req: *http.Request, resp: *http.Response) anyerror!http.StatusCode {
        _ = allocator;
        _ = resp;

        const self: *PostFiles = @ptrCast(@alignCast(ptr));

        if (req.path_segments.len < 1) {
            return http.StatusCode.bad_request;
        }

        const filename = req.path_segments[1];

        var dir = try std.fs.openDirAbsolute(self.directory, .{ .iterate = true });
        defer dir.close();

        var file = try dir.createFile(filename, .{});
        defer file.close();

        try file.writeAll(req.body.?);

        return http.StatusCode.created;
    }

    pub fn handler(self: *PostFiles) http.Handler {
        return .{
            .ptr = self,
            .handleFn = handle,
        };
    }
};
