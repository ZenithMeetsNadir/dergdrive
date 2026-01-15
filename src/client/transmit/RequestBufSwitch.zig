const std = @import("std");
const BufferSwitch = @import("BufferSwitch.zig");
const Cryptors = @import("Cryptors.zig");
const sync = @import("dergdrive").proto.sync;
const IdSupplier = sync.RequestChunk.IdSupplier;
const TransmitFileMsg = sync.templates.TransmitFileMsg;

const RequestBufSwitch = @This();

buf_switch: BufferSwitch = .{},
msgs: [Cryptors.num_workers]TransmitFileMsg,
id_supply: *sync.RequestChunk.IdSupplier,

pub fn init(id_supply: *sync.RequestChunk.IdSupplier) RequestBufSwitch {
    var rbs: RequestBufSwitch = .{
        .msgs = undefined,
        .id_supply = id_supply,
    };

    for (rbs.msgs, 0..) |*msg, idx| {
        msg.* = .init(&rbs.buf_switch.buffers[idx], id_supply) catch unreachable;
    }

    return rbs;
}
