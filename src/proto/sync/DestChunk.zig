const std = @import("std");
const Chunk = @import("Chunk.zig");
const crypt = @import("dergdrive").crypt;

const DestChunk = @This();

pub const header_title = "dest";
pub const chunk_name_size = crypt.NameHashAlgo.digest_length;
pub const content_size = chunk_name_size + @sizeOf(u32);

back_chunk: Chunk,
block_name: [chunk_name_size]u8 = undefined,
offset: u32,

pub fn fromChunk(chunk: Chunk) DestChunk {
    var dest_chunk: DestChunk = .{
        .back_chunk = chunk,
        .offset = std.mem.readInt(u32, chunk.data[chunk_name_size..content_size], .little),
    };

    std.mem.copyForwards(u8, &dest_chunk.block_name, chunk.data[0..chunk_name_size]);

    return dest_chunk;
}

pub fn write(self: DestChunk) void {
    std.mem.copyForwards(u8, self.back_chunk.data, &self.block_name);
    std.mem.writeInt(u32, self.back_chunk.data[chunk_name_size..content_size], self.offset, .little);
}
