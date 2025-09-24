const std = @import("std");

pub const proto = struct {
    pub const SyncMessage = @import("proto/sync/SyncMessage.zig");
    pub const RequestChunk = @import("proto/sync/RequestChunk.zig");
};

pub const crypt = @import("crypt/crypt.zig");
pub const conf = @import("conf/conf.zig");
pub const Env = @import("conf/Env.zig");

pub const cli = struct {
    pub const prompt = @import("cli/prompt.zig");
};

test {
    std.testing.refAllDecls(@This());
}
