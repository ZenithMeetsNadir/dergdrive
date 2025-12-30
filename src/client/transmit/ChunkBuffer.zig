const std = @import("std");
const Thread = std.Thread;

const ChunkBuffer = @This();

pub const chunk_size = 0x400000; // 4 MiB

back_buf: [chunk_size]u8 = undefined,
data_len: usize = 0,
empty: bool = false,
w_lock: Thread.Mutex = .{},
state_cond: Thread.Condition = .{},

pub fn waitUntilState(self: *ChunkBuffer, empty: bool) void {
    self.w_lock.lock();
    defer self.w_lock.unlock();

    while (self.empty != empty)
        self.state_cond.wait(&self.w_lock);
}

pub fn signalState(self: *ChunkBuffer, empty: bool) void {
    self.w_lock.lock();
    defer self.w_lock.unlock();

    self.empty = empty;
    self.state_cond.signal();
}
