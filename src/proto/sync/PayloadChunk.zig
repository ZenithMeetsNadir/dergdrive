const std = @import("std");
const Chunk = @import("Chunk.zig");

const PayloadChunk = @This();

pub const header_title: []const u8 = "payd";

payload: []const u8,

pub inline fn fromChunk(chunk: Chunk) Chunk.ReadError!PayloadChunk {
    return .{ .payload = chunk.data };
}
