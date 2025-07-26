const http = @import("http.zig");

pub fn root(req: *http.Request, resp: *http.Response) anyerror!http.StatusCode {
    _ = req;
    _ = resp;

    return http.StatusCode.ok;
}

pub fn userAgent(req: *http.Request, resp: *http.Response) anyerror!http.StatusCode {
    try resp.setHeader(http.Header.content_type, "text/plain");
    try resp.setBody(req.headers.get(http.Header.user_agent) orelse return http.Error.InvalidRequest);

    return http.StatusCode.ok;
}

pub fn echo(req: *http.Request, resp: *http.Response) anyerror!http.StatusCode {
    if (req.path_segments.len > 1) {
        try resp.setHeader(http.Header.content_type, "text/plain");
        try resp.setBody(req.path_segments[1]);
    }

    return http.StatusCode.ok;
}
