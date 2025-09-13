const std = @import("std");

const SyncMessage = @This();

pub const SyncMessageError = error{InvalidHeader};

pub const header_title: []const u8 = "sync";
pub const message_size_size = @sizeOf(usize);
pub const header_size = header_title.len + message_size_size;

header: [header_size]u8 = undefined,
data: []const u8,

pub fn decomposeMsg(msg: []const u8) SyncMessageError!SyncMessage {
    if (msg.len < header_size)
        return SyncMessageError.InvalidHeader;

    if (!std.mem.eql(u8, msg[0..header_title.len], header_title))
        return SyncMessageError.InvalidHeader;

    const size = std.mem.readInt(usize, msg[header_title.len..header_size], .little);
    if (msg.len < header_size + size)
        return SyncMessageError.InvalidHeader;

    var sync_msg: SyncMessage = .{ .data = msg[header_size .. header_size + size] };
    std.mem.copyForwards(u8, &sync_msg.header, msg[0..header_size]);

    return sync_msg;
}

pub fn composeMsg(data: []const u8) SyncMessage {
    var sync_msg: SyncMessage = .{ .data = data };
    std.mem.copyForwards(u8, sync_msg.header[0..header_title.len], header_title);
    std.mem.writeInt(usize, sync_msg.header[header_title.len..header_size], data.len, .little);
    return sync_msg;
}
