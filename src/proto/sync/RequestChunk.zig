const std = @import("std");
const Chunk = @import("Chunk.zig");
const SyncMessage = @import("SyncMessage.zig");

const RequestChunk = @This();

pub const ReadError = error{UnknownRequestType} || Chunk.ReadError;

pub const RequestError = error{
    IsRequest,
    Ok,
    GenericError,
};

pub const ExhaustiveRequestError = RequestError;

pub const header_title: []const u8 = "rqst";
pub const IdT = u32;
pub const id_size = @sizeOf(IdT);
pub const request_type_size = @sizeOf(RequestType);
pub const RespCodeT = u16;
pub const resp_code_size = @sizeOf(RespCodeT);
pub const content_size = id_size + request_type_size + resp_code_size;

pub const RequestType = enum(u16) {
    vol_add,
    vol_delete,
    mfest_fetch,
    mfest_post,
    files_request,
    file_post,
};

id: IdT,
request_type: RequestType,
resp_code: RespCodeT = @intFromError(RequestError.IsRequest),

pub fn fromChunk(chunk: Chunk) ReadError!RequestChunk {
    const id = std.mem.readInt(IdT, chunk.data[0..id_size], .little);

    const req_type_num = std.mem.readInt(@typeInfo(RequestType).@"enum".tag_type, chunk.data[id_size .. id_size + request_type_size], .little);
    if (req_type_num > @as(u16, @intFromEnum(RequestType.file_delete)))
        return ReadError.UnknownRequestType;

    const resp_code = std.mem.readInt(RespCodeT, chunk.data[id_size + request_type_size .. id_size + request_type_size + resp_code_size], .little);

    return .{
        .id = id,
        .request_type = @enumFromInt(req_type_num),
        .resp_code = resp_code,
        .data = chunk.data[content_size..],
    };
}

pub fn setErrorValue(self: *RequestChunk, err: RequestError) void {
    self.resp_code = @intFromError(err);
}
