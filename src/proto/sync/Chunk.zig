const std = @import("std");
const header = @import("header.zig");
const SyncMessage = @import("SyncMessage.zig");
const RequestChunk = @import("RequestChunk.zig");
const PayloadChunk = @import("PayloadChunk.zig");

pub const Iterator = struct {
    buffer: []const u8,
    index: usize = 0,

    pub fn next(self: *Iterator) ReadError!?Chunk {
        if (self.index >= self.buffer.len) return null;

        const chunk = try readChunk(self.buffer[self.index..]);
        self.index += chunk.getWriteSize();

        return chunk;
    }
};

pub const ChunkType = enum {
    sync_message,
    request,
    payload,

    const PackedStrT = @Type(std.builtin.Type.Int{ .bits = 8 * header.header_title_size });
    fn packedString(title: [header.header_title_size]u8) PackedStrT {
        return @as(*PackedStrT, @ptrCast(&title)).*;
    }

    pub fn fromHeaderTitle(title: [header.header_title_size]u8) ?ChunkType {
        return switch (packedString(title)) {
            packedString(SyncMessage.header_title) => .sync_message,
            packedString(RequestChunk.header_title) => .request,
            packedString(PayloadChunk.header_title) => .payload,
            else => null,
        };
    }
};

const Chunk = @This();

pub const ReadError = error{
    InvalidHeader,
    UnknownChunkType,
    DataLenMismatch,
};

chunk_type: ChunkType,
data: []const u8,

pub inline fn getWriteSize(self: Chunk) usize {
    return header.header_size + self.data.len;
}

pub fn readChunk(buffer: []const u8) ReadError!Chunk {
    if (buffer.len < header.header_size)
        return ReadError.InvalidHeader;

    const size = std.mem.readInt(header.DataLenT, buffer[header.header_title_size .. header.header_title_size + header.data_len_size], .little);
    if (buffer.len < header.header_size + size)
        return ReadError.DataLenMismatch;

    return .{
        .data = buffer[header.header_size .. header.header_size + size],
        .chunk_type = ChunkType.fromHeaderTitle(buffer[0..header.header_title_size]) orelse return ReadError.UnknownChunkType,
    };
}

pub fn as(chunk: Chunk, comptime ChunkT: type) anyerror!ChunkT {
    if (std.meta.hasFn(ChunkT, "fromChunk")) {
        return try ChunkT.fromChunk(chunk);
    } else return .{ .data = chunk.data };
}
