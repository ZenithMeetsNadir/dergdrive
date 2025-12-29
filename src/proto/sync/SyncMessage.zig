const std = @import("std");
const header = @import("header.zig");
const Chunk = @import("Chunk.zig");
const RequestChunk = @import("RequestChunk.zig");

const SyncMessage = @This();

pub const IterFromBufError = error{ConvertFailed} || Chunk.ReadError;

pub const header_title: [header.header_title_size]u8 = "dsnc";

data: []const u8,

pub fn iterFromBuf(buffer: []const u8) IterFromBufError!Chunk.Iterator {
    const chunk = try Chunk.readChunk(buffer);
    const s_msg = chunk.as(SyncMessage) catch return IterFromBufError.ConvertFailed;
    return .{ .buffer = s_msg.data };
}

pub inline fn getWriteSize(self: SyncMessage) usize {
    return header.header_size + self.data.len;
}

pub fn writeMsg(self: SyncMessage, buffer: []u8) usize {
    const write_size = self.getWriteSize();
    std.debug.assert(buffer.len >= write_size);

    std.mem.copyForwards(u8, buffer[0..header.header_title_size], &header_title);
    std.mem.writeInt(header.DataLenT, buffer[header.header_title_size .. header.header_title_size + header.data_len_size], self.data.len, .little);
    std.mem.copyForwards(u8, buffer[header.header_size .. header.header_size + self.data.len], self.data);

    return write_size;
}
