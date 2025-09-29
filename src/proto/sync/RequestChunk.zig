const std = @import("std");
const SyncMessage = @import("SyncMessage.zig");

const RequestChunk = @This();

pub const RequestChunkError = error{
    InvalidHeader,
    UnknownRequestType,
};

pub const FetchManifestResponseError = std.mem.Allocator.Error || RequestChunkError;

pub const RequestError = error{
    Ok,
    GenericError,
    Blocked,
    MissingSendFn,
    SendFailed,
};

pub const ExhaustiveRequestError = RequestError;

pub const header_title: []const u8 = "rqst";
pub const id_size = @sizeOf(u32);
pub const request_type_size = @sizeOf(RequestType);
pub const request_size_size = @sizeOf(u16);
pub const resp_code_size = @sizeOf(u16);
pub const header_size = header_title.len + id_size + request_type_size + request_size_size + resp_code_size;

pub const RequestType = enum(u16) {
    user_list,
    user_add,
    user_remove,
    user_auth,
    user_deauth,
    mfest_fetch,
    mfest_update,
    file_fetch,
    file_fetch_chunk,
    file_alloc,
    file_update,
    file_update_chunk,
    file_delete,

    pub fn blockFileTransfer(self: RequestType) bool {
        return switch (self) {
            .file_fetch, .file_update => true,
            else => false,
        };
    }
};

header: [header_size]u8 = undefined,
id: u32,
request_type: RequestType,
resp_code: u16 = @intFromError(RequestError.Ok),
data: []const u8,
allocator: ?std.mem.Allocator = null,

pub fn deinit(self: RequestChunk) void {
    if (self.allocator) |allocator|
        allocator.free(self.data);
}

pub fn isolateRequestChunk(msg: SyncMessage) RequestChunkError!RequestChunk {
    if (msg.data.len < header_size)
        return RequestChunkError.InvalidHeader;

    if (!std.mem.eql(u8, msg.data[0..header_title.len], header_title))
        return RequestChunkError.InvalidHeader;

    const id = std.mem.readInt(u32, msg.data[header_title.len .. header_title.len + id_size], .little);

    const req_type_num = std.mem.readInt(u16, msg.data[header_title.len + id_size .. header_title.len + id_size + request_type_size], .little);
    if (req_type_num > @as(u16, @intFromEnum(RequestType.file_delete)))
        return RequestChunkError.UnknownRequestType;

    const resp_code = std.mem.readInt(u16, msg.data[header_title.len + id_size + request_type_size .. header_title.len + id_size + request_type_size + resp_code_size], .little);

    const size = std.mem.readInt(u16, msg.data[header_title.len + id_size + request_type_size + resp_code_size .. header_size], .little);
    if (msg.data.len < header_size + size)
        return RequestChunkError.InvalidHeader;

    var req_chunk: RequestChunk = .{
        .id = id,
        .request_type = @enumFromInt(req_type_num),
        .resp_code = resp_code,
        .data = msg.data[header_size .. header_size + size],
    };
    std.mem.copyForwards(u8, &req_chunk.header, msg.data[0..header_size]);

    return req_chunk;
}

pub fn sourceRequestChunk(msg: SyncMessage) RequestChunkError!RequestChunk {
    var req_chunk = try isolateRequestChunk(msg);
    req_chunk.header = msg.data[0..header_size];
    return req_chunk;
}

pub fn setErrorValue(self: *RequestChunk, err: RequestError) void {
    self.resp_code = @intFromError(err);
    std.mem.writeInt(u16, self.header[header_title.len + id_size + request_type_size .. header_title.len + id_size + request_type_size + resp_code_size], self.resp_code, .little);
}

pub fn constructRequestChunk(req_type: RequestType, data: []const u8) RequestChunk {
    var req_chunk: RequestChunk = .{ .request_type = req_type, .data = data };
    std.mem.copyForwards(u8, req_chunk.header[0..header_title.len], header_title);
    std.mem.writeInt(u32, req_chunk.header[header_title.len .. header_title.len + id_size], req_chunk.id, .little);
    std.mem.writeInt(u16, req_chunk.header[header_title.len + id_size .. header_title.len + id_size + request_type_size], @as(u16, @intFromEnum(req_type)), .little);
    req_chunk.setErrorValue(RequestError.Ok);
    std.mem.writeInt(u16, req_chunk.header[header_title.len + id_size + request_type_size .. header_title.len + id_size + request_type_size + resp_code_size], req_chunk.resp_code, .little);
    std.mem.writeInt(u16, req_chunk.header[header_title.len + id_size + request_type_size + resp_code_size .. header_size], @as(u16, data.len), .little);
    return req_chunk;
}

pub fn fetchManifestRequest() RequestChunk {
    return constructRequestChunk(.mfest_fetch, &.{});
}

pub fn fetchManifestResponse(msg: SyncMessage, allocator: std.mem.Allocator) FetchManifestResponseError![]const u8 {
    const req_chunk = try isolateRequestChunk(msg);
    return try allocator.dupe(u8, msg.data[header_size + req_chunk.data.len ..]);
}
