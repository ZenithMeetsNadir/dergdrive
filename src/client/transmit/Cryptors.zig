const std = @import("std");
const Mutex = std.Thread.Mutex;
const BufferSwitch = @import("BufferSwitch.zig");
const ChunkBuffer = @import("ChunkBuffer.zig");
const crypt = @import("dergdrive").crypt;
const AtomicBool = std.atomic.Value(bool);

const Cryptors = @This();

// encrypted format: auth_tag | nonce | encrypted_content

const Cryptor = struct {
    pub const InitError = error{NotEnoughResources};

    group: *Cryptors,
    switch_idx: u8,
    raw: *ChunkBuffer,
    enc: *ChunkBuffer,
    running: AtomicBool = .init(false),

    pub fn init(group: *Cryptors) InitError!Cryptor {
        const switch_idx = group.switch_idx;
        if (switch_idx >= num_workers)
            return InitError.NotEnoughResources;

        group.switch_idx += 1;

        return .{
            .group = group,
            .switch_idx = switch_idx,
            .raw = &group.raw_switch.buffers[switch_idx],
            .enc = &group.enc_switch.buffers[switch_idx],
        };
    }

    pub fn pipeEncrypted(self: *Cryptor) !void {
        while (self.running.load(.acquire)) {
            self.raw.waitUntilState(.full);
            self.enc.waitUntilState(.empty);

            const in_buf = self.raw.back_buf[0..self.raw.data_len];
            const out_buf = &[_]u8{}; // TODO claim network enc content buffer here

            var auth_tag: [crypt.AesAlgo.tag_length]u8 = undefined;
            var nonce: [crypt.AesAlgo.nonce_length]u8 = undefined;
            std.crypto.random.bytes(&nonce);

            crypt.AesAlgo.encrypt(out_buf, &auth_tag, in_buf, &nonce, &nonce, &self.group.key);

            self.group.raw_switch.signalAvailable(self.switch_idx);
            // TODO signal network buffer ready
        }
    }

    pub fn pipeDecrypted(self: *Cryptor) !void {
        while (self.running.load(.acquire)) {
            // TODO wait for network buffer to be ready
            self.raw.waitUntilState(true);

            var in_buf = &[_]u8{}; // TODO get network enc content buffer here
            const auth_tag = in_buf[0..crypt.AesAlgo.tag_length];
            const nonce = in_buf[crypt.AesAlgo.tag_length..crypt.nonce_auth_len];
            in_buf = in_buf[crypt.nonce_auth_len..];

            const out_buf = self.raw.back_buf[0..in_buf.len];

            // TODO report integrity violation
            crypt.AesAlgo.decrypt(out_buf, in_buf, auth_tag, nonce, nonce, &self.group.key) catch continue;

            {
                self.raw.w_lock.lock();
                defer self.raw.w_lock.unlock();

                self.raw.data_len = out_buf.len;
            }

            // TODO signal network buffer available
            self.group.raw_switch.signalAvailable(self.switch_idx);
        }
    }
};

pub const num_workers = 4;

raw_switch: *BufferSwitch,
enc_switch: *BufferSwitch,

key: [crypt.key_length]u8,
switch_idx: u8 = 0,
th_pool: std.Thread.Pool = undefined,
encs: [num_workers]Cryptor = undefined,
allocator: std.mem.Allocator,

pub fn runPipe(self: *Cryptors) std.mem.Allocator.Error!void {
    self.th_pool.init(.{ .allocator = self.allocator, .n_jobs = num_workers });

    for (&self.encs) |*enc| {
        enc.* = .init(self) catch unreachable;
        enc.running.store(true, .release);
        try self.th_pool.spawn(Cryptor.pipeEncrypted, .{enc});
    }
}

pub fn stopPipe(self: *Cryptors) void {
    for (&self.encs) |*enc| {
        enc.running.store(false, .release);
    }

    self.th_pool.deinit();
}
