const std = @import("std");
const Mutex = std.Thread.Mutex;
const BufferSwitch = @import("BufferSwitch.zig");
const ChunkBuffer = @import("ChunkBuffer.zig");
const crypt = @import("dergdrive").crypt;

const Encryptors = @This();

const Encryptor = struct {
    pub const InitError = error{NotEnoughResources};

    group: *Encryptors,
    in: *ChunkBuffer,

    pub fn init(group: *Encryptors) InitError!Encryptor {
        group.idx_assign_lock.lock();
        defer group.idx_assign_lock.unlock();

        const switch_idx = group.switch_idx;
        if (switch_idx >= num_workers)
            return InitError.NotEnoughResources;

        group.switch_idx += 1;

        return .{
            .group = group,
            .in = &group.in.buffers[switch_idx],
        };
    }
};

pub const num_workers = 4;

in: *BufferSwitch,
key: [crypt.key_length]u8,
switch_idx: u8 = 0,
idx_assign_lock: Mutex = .{},
th_pool: std.Thread.Pool = undefined,

pub fn init(in: *BufferSwitch, key: [crypt.key_length]u8, allocator: std.mem.Allocator) Encryptors {
    var enc: Encryptors = .{
        .in = in,
        .key = key,
    };

    enc.th_pool.init(.{ .allocator = allocator, .n_jobs = num_workers });

    return enc;
}
