const std = @import("std");
const net = @import("net");

const TransmitChunker = @This();

pub const PipeError = net.TcpClient.SendError || error{ReadFailed};

pub const buffer_size: usize = 0x20000; // 128 kB

client: *const net.TcpClient,
back_buffer: [buffer_size]u8 = undefined,
chunk_buffer: [buffer_size]u8 = undefined,

pub fn pipe(self: *TransmitChunker, file: std.fs.File) PipeError!void {
    while (true) {
        const bytes_read = file.reader(&self.back_buffer).read(&self.chunk_buffer) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return PipeError.ReadFailed,
        };

        try self.client.send(self.chunk_buffer[0..bytes_read]);

        if (bytes_read < buffer_size) break;
    }
}
