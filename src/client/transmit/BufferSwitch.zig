const std = @import("std");
const ChunkBuffer = @import("ChunkBuffer.zig");
const Cryptors = @import("Cryptors.zig");
const Mutex = std.Thread.Mutex;

const BufferSwitch = @This();

buffers: [Cryptors.num_workers]ChunkBuffer = .{.{}} ** Cryptors.num_workers,
empty_buf_idx: u8 = Cryptors.num_workers,
buf_idx_lock: Mutex = .{},
avail_cond: std.Thread.Condition = .{},

pub fn waitUntilAvailable(self: *BufferSwitch) u8 {
    self.buf_idx_lock.lock();
    defer self.buf_idx_lock.unlock();

    while (self.empty_buf_idx == Cryptors.num_workers)
        self.avail_cond.wait(&self.buf_idx_lock);

    const idx = self.empty_buf_idx;
    self.empty_buf_idx = Cryptors.num_workers;
    return idx;
}

pub fn signalAvailable(self: *BufferSwitch, idx: u8) void {
    self.buf_idx_lock.lock();
    defer self.buf_idx_lock.unlock();

    self.empty_buf_idx = idx;
    self.avail_cond.signal();
}

pub fn claimBuf(self: *BufferSwitch, is_write: bool) []u8 {
    for (0..Cryptors.num_workers + 1) |i| {
        const idx = if (i == Cryptors.num_workers) self.waitUntilAvailable() else i;
        var buf = &self.buffers[idx];

        buf.w_lock.lock();
        defer buf.w_lock.unlock();

        if ((buf.empty == .empty) == is_write) {
            buf.data_len = 0;
            return &buf.back_buf;
        }
    }
}

pub fn unclaimBuf(self: *BufferSwitch, used_buf: []u8, is_write: bool) void {
    for (self.buffers) |*buf| {
        if (&buf.back_buf == used_buf.ptr)
            buf.signalState(if (is_write) .full else .empty);
    }
}
