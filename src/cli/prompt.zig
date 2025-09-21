const std = @import("std");

pub fn promptUser(comptime fmt: []const u8, args: anytype, allocator: std.mem.Allocator) ![]const u8 {
    _ = fmt;
    _ = args;
    _ = allocator;
    return "y";
}
