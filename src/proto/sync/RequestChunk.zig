const std = @import("std");
const SyncMessage = @import("SyncMessage.zig");

const RequestChunk = @This();

pub const RequestChunkError = error{
    InvalidHeader,
    UnknownRequestType,
};

pub const header_title: []const u8 = "rqst";
pub const request_type_size = @sizeOf(u16);
pub const request_size_size = @sizeOf(u16);
pub const header_size = header_title.len + request_type_size + request_size_size;

pub const RequestType = enum(u32) {
    mfest_fetch,
    mfest_fetch_resp,
    mfest_update,
    mfest_update_resp,
    file_fetch,
    file_fetch_resp,
    file_post,
    file_post_resp,
    file_update,
    file_update_resp,
    file_delete,
    file_delete_resp,
};

header: [header_size]u8 = undefined,
request_type: RequestType,
data: []const u8,

pub fn isolateRequestChunk(msg: SyncMessage) RequestChunkError!RequestChunk {
    if (msg.data.len < header_size)
        return RequestChunkError.InvalidHeader;

    if (!std.mem.eql(u8, msg.data[0..header_title.len], header_title))
        return RequestChunkError.InvalidHeader;

    const req_type_num = std.mem.readInt(u16, msg.data[header_title.len .. header_title.len + request_type_size], .little);
    if (req_type_num > @as(u16, @intFromEnum(RequestType.file_delete)))
        return RequestChunkError.UnknownRequestType;

    const size = std.mem.readInt(u16, msg.data[header_title.len + request_type_size .. header_size], .little);
    if (msg.data.len < header_size + size)
        return RequestChunkError.InvalidHeader;

    var req_chunk: RequestChunk = .{
        .request_type = @enumFromInt(req_type_num),
        .data = msg.data[header_size .. header_size + size],
    };
    std.mem.copyForwards(u8, &req_chunk.header, msg.data[0..header_size]);

    return req_chunk;
}

pub fn constructRequestChunk(req_type: RequestType, data: []const u8) RequestChunk {
    var req_chunk: RequestChunk = .{ .request_type = req_type, .data = data };
    std.mem.copyForwards(u8, req_chunk.header[0..header_title.len], header_title);
    std.mem.writeInt(u16, req_chunk.header[header_title.len .. header_title.len + request_type_size], @as(u16, @intFromEnum(req_type)), .little);
    std.mem.writeInt(u16, req_chunk.header[header_title.len + request_type_size .. header_size], @as(u16, data.len), .little);
    return req_chunk;
}
