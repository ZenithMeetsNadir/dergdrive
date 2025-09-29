const std = @import("std");
const SyncMessage = @import("SyncMessage.zig");
const RequestChunk = @import("RequestChunk.zig");
const AtomicBool = std.atomic.Value(bool);

const RequestQueue = @This();

pub const SendRequestError = error{};

const Request = struct {
    request: SyncMessage,
    response: SyncMessage,
    mutex: std.Thread.Mutex = .{},
    cond: std.Thread.Condition = .{},
    sent: bool = false,
    received: bool = false,
    interrupt: bool = false,
};

blocked_queue: std.ArrayList(*Request) = .empty,
pending_queue: std.ArrayList(*Request) = .empty,
queue_lock: std.Thread.Mutex = .{},
allocator: std.mem.Allocator,
running: AtomicBool = .init(false),
file_transfer_block: ?*Request = null,
sender_thread: std.Thread = undefined,
send_fn: ?fn (req: *Request) SendRequestError!void = null,

pub fn init(allocator: std.mem.Allocator) !RequestQueue {
    return .{ .allocator = allocator };
}

fn dispatchQueue(self: *RequestQueue) !void {
    while (self.running.load(.acquire)) {
        std.Thread.yield();
        self.queue_lock.lock();
        defer self.queue_lock.unlock();

        var i: usize = 0;
        while (i < self.blocked_queue.items.len) : (i += 1) {
            const req = self.blocked_queue.items[i];

            self.blockedQueueErrorNet(req) catch continue;

            try self.pending_queue.append(self.allocator, self.blocked_queue.orderedRemove(i));
        }
    }
}

fn blockedQueueErrorNet(self: *RequestQueue, req: *Request) (RequestChunk.RequestChunkError || SendRequestError || error{ Blocked, SendFnNull })!void {
    req.mutex.lock();
    errdefer {
        req.interrupt = true;
        req.cond.signal();
    }
    defer req.mutex.unlock();

    var req_chunk = try RequestChunk.sourceRequestChunk(req.request);

    if (req_chunk.request_type.blockFileTransfer()) {
        if (self.file_transfer_block) |block| {
            block.mutex.lock();
            defer block.mutex.unlock();

            if (!block.received) {
                req_chunk.setErrorValue(RequestChunk.RequestError.Blocked);
                return error.Blocked;
            }
        }
    }

    if (self.send_fn) |send_fn| {
        req.mutex.unlock();

        send_fn(req) catch |err| {
            req_chunk.setErrorValue(RequestChunk.RequestError.SendFailed);
            return err;
        };

        req.mutex.lock();
        req.sent = true;
    } else {
        req_chunk.setErrorValue(RequestChunk.RequestError.MissingSendFn);

        return error.SendFnNull;
    }

    if (req_chunk.request_type.blockFileTransfer())
        self.file_transfer_block = req;
}

pub fn open(self: *RequestQueue) std.Thread.SpawnError!void {
    if (!self.running.load(.acquire)) {
        self.running.store(true, .release);
        self.sender_thread = try std.Thread.spawn(dispatchQueue, self);
    }
}

pub fn close(self: *RequestQueue) void {
    if (self.running.load(.acquire)) {
        self.running.store(false, .release);
        self.sender_thread.join();

        self.blocked_queue.deinit(self.allocator);
        self.pending_queue.deinit(self.allocator);
    }
}
