const std = @import("std");
const ChunkBuffer = @import("ChunkBuffer.zig");
const Encryptors = @import("Encryptors.zig");
const Mutex = std.Thread.Mutex;

const BufferSwitch = @This();

buffers: [Encryptors.num_workers]ChunkBuffer = .{.{}} ** Encryptors.num_workers,
emtpy_buf_idx: u8 = Encryptors.num_workers,
buf_idx_lock: Mutex = .{},
avail_cond: std.Thread.Condition = .{},

pub fn waitUntilAvailable(self: *BufferSwitch) u8 {
    self.buf_idx_lock.lock();
    defer self.buf_idx_lock.unlock();

    while (self.emtpy_buf_idx == Encryptors.num_workers)
        self.avail_cond.wait(&self.buf_idx_lock);

    const idx = self.emtpy_buf_idx;
    self.emtpy_buf_idx = Encryptors.num_workers;
    return idx;
}

pub fn signalAvailable(self: *BufferSwitch, idx: u8) void {
    self.buf_idx_lock.lock();
    defer self.buf_idx_lock.unlock();

    self.emtpy_buf_idx = idx;
    self.avail_cond.signal();
}

pub fn claimBuf(self: *BufferSwitch, write: bool) []u8 {
    for (0..Encryptors.num_workers + 1) |i| {
        const idx = if (i == Encryptors.num_workers) self.waitUntilAvailable() else i;
        var buf = &self.buffers[idx];

        buf.w_lock.lock();
        defer buf.w_lock.unlock();

        if (buf.empty == write) {
            buf.data_len = 0;
            return &buf.back_buf;
        }
    }
}

pub fn unclaimBuf(self: *BufferSwitch, used_buf: []u8, write: bool) void {
    for (self.buffers) |*buf| {
        if (&buf.back_buf == used_buf.ptr)
            buf.signalState(!write);
    }
}
