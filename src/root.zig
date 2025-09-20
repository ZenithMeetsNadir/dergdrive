pub const proto = struct {
    pub const SyncMessage = @import("proto/sync/SyncMessage.zig");
    pub const RequestChunk = @import("proto/sync/RequestChunk.zig");
};

pub const crypt = @import("crypt/crypt.zig");
