const http = @import("http.zig");

pub const Root = struct {
    fn handle(ptr: *anyopaque, req: *http.Request, resp: *http.Response) anyerror!http.StatusCode {
        _ = ptr;
        _ = req;
        _ = resp;

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
    fn handle(ptr: *anyopaque, req: *http.Request, resp: *http.Response) anyerror!http.StatusCode {
        _ = ptr;

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
    fn handle(ptr: *anyopaque, req: *http.Request, resp: *http.Response) anyerror!http.StatusCode {
        _ = ptr;

        if (req.path_segments.len > 1) {
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

pub const Files = struct {
    directory: []const u8,

    fn handle(ptr: *anyopaque, req: *http.Request, resp: *http.Response) anyerror!http.StatusCode {
        const self: *Files = @ptrCast(@alignCast(ptr));
        _ = req;

        // TODO implement

        try resp.setBody(self.directory);

        return http.StatusCode.ok;
    }

    pub fn handler(self: *Files) http.Handler {
        return .{
            .ptr = self,
            .handleFn = handle,
        };
    }
};
