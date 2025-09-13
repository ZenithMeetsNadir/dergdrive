const std = @import("std");
const net = @import("net");

const TransmitChunker = @This();

pub const PipeFileError = net.TcpClient.SendError || error{ReadFailed};

pub const buffer_size: usize = 0x20000; // 128 kiB

client: net.TcpClient,

back_buffer: [buffer_size]u8 = undefined,
chunk_buffer: [buffer_size]u8 = undefined,

pub fn pipeFile(self: *TransmitChunker, file: std.fs.File) PipeFileError!void {
    while (true) {
        const bytes_read = file.reader(&self.back_buffer).read(&self.chunk_buffer) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return PipeFileError.ReadFailed,
        };

        try self.client.send(self.chunk_buffer[0..bytes_read]);

        if (bytes_read < buffer_size) break;
    }
}
