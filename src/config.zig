const std = @import("std");

pub fn Config(T: anytype) type {
    return struct {
        const Self = Config(T);

        allocator: std.mem.Allocator,
        vals: T,
        args: ?[][:0]u8 = null,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .vals = T{},
            };
        }

        pub fn deinit(self: *Self) void {
            if (self.args != null) self.allocator.free(self.args.?);
        }

        pub fn setValue(self: *Self, comptime field: []const u8, val: anytype) void {
            @field(self.vals, field) = val;
        }

        pub fn parseFlags(self: *Self) !void {
            const config_fields = std.meta.fields(T);
            self.args = try std.process.argsAlloc(self.allocator);
            const args = self.args.?;

            var i: usize = 0;
            while (i < args.len) {
                const trimmed_arg = std.mem.trimLeft(u8, args[i], "--");

                inline for (config_fields) |field| {
                    if (trimmed_arg.len > 0 and std.mem.eql(u8, field.name, trimmed_arg)) {
                        i += 1;
                        if (i >= args.len) return error.InvalidInput;

                        const FieldType = field.type;
                        const val_str = args[i];

                        switch (FieldType) {
                            []const u8 => self.setValue(field.name, val_str),
                            u16 => {
                                const parsed_val = try std.fmt.parseInt(u16, val_str, 10);
                                self.setValue(field.name, parsed_val);
                            },
                            else => @compileError("Unsupported config type: " ++ @typeName(FieldType)),
                        }
                    }
                }

                i += 1;
            }
        }
    };
}
