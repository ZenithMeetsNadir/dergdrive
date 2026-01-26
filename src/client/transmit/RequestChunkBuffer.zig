const std = @import("std");
const ChunkBuffer = @import("ChunkBuffer.zig");
const sync = @import("dergdrive").proto.sync;
const IdSupplier = sync.RequestChunk.IdSupplier;
const TransmitFileMsg = sync.templates.TransmitFileMsg;

const RequestChunkBuffer = @This();

chunk_buf: ChunkBuffer = .{ .buf_len = ChunkBuffer.chunk_size },
sync_msg: sync.SyncMessage,
trns_msg: TransmitFileMsg,
id_supply: *IdSupplier,

pub fn init(id_supply: *IdSupplier) RequestChunkBuffer {
    var rcb = RequestChunkBuffer{
        .chunk_buf = .{ .buf_len = ChunkBuffer.chunk_size },
        .sync_msg = undefined,
        .trns_msg = undefined,
        .id_supply = id_supply,
    };

    rcb.sync_msg = .{ .msg_buf = &rcb.chunk_buf };

    return rcb;
}

pub fn initTransmitFileMsg(self: *RequestChunkBuffer) void {
    self.trns_msg = .init(self.sync_msg.msg_buf, self.id_supply);
}
