const std = @import("std");
const ChunkBuffer = @import("ChunkBuffer.zig");
const sync = @import("dergdrive").proto.sync;
const Cryptor = @import("Cryptor.zig");

pub const RequestParams = union {
    file_post: struct {
        dest: sync.DestChunk,
    },
    file_new: void,
};

const RawFileChunkBuffer = @This();

chunk_buf: ChunkBuffer = .{ .buf_len = ChunkBuffer.chunk_size - (Cryptor.enc_add_info_len + sync.templates.TransmitFileMsg.non_payload_size) },
request: sync.RequestChunk = undefined,
request_params: RequestParams = undefined,
