const std = @import("std");

pub const cli = struct {
    pub const prompt = @import("cli/prompt.zig");
};

pub const client = struct {
    pub const track = struct {
        pub const IncludeTree = @import("client/track/IncludeTree.zig");
    };
};

pub const conf = struct {
    pub const conf = @import("conf/conf.zig");
    pub const Env = @import("conf/Env.zig");
};

pub const crypt = @import("crypt/crypt.zig");

pub const proto = struct {
    pub const sync = struct {
        pub const SyncMessage = @import("proto/sync/SyncMessage.zig");
        pub const RequestChunk = @import("proto/sync/RequestChunk.zig");
    };
};

test {
    std.testing.refAllDeclsRecursive(@This());
}
