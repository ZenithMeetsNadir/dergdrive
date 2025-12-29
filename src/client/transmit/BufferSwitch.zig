const std = @import("std");
const ChunkBuffer = @import("ChunkBuffer.zig");
const Encryptors = @import("Encryptors.zig");

const BufferSwitch = @This();

buffers: [Encryptors.num_workers]ChunkBuffer = .{.{}} ** Encryptors.num_workers,
buf_idx: usize = 0,

pub fn claimBuf(self: *BufferSwitch) []u8 {
    var cur_idx = self.buf_idx + 1;

    while (true) : (cur_idx += 1) {
        var buf = &self.buffers[cur_idx % Encryptors.num_workers];

        if (cur_idx % Encryptors.num_workers == self.buf_idx)
            buf.waitUntilEmpty(true);

        buf.w_lock.lock();
        defer buf.w_lock.unlock();

        if (buf.empty) {
            self.buf_idx = (self.buf_idx + 1) % Encryptors.num_workers;
            buf.data_len = 0;
            return &buf.back_buf;
        }
    }
}

pub fn finishTransaction(self: *BufferSwitch, used_buf: []u8) void {
    for (self.buffers) |*buf| {
        if (&buf.back_buf == used_buf.ptr)
            buf.finish(false);
    }
}
