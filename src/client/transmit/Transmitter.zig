const std = @import("std");
const net = @import("net");
const root = @import("dergdrive");
const proto = root.proto;
const crypt = root.crypt;
const aes = crypt.aes;

const Transmitter = @This();

pub const PipeFileError = net.TcpClient.SendError || error{ReadFailed};
pub const PostFileError = PipeFileError || std.fs.File.StatError;

pub const buffer_size: usize = 0x20000; // 128 kiB
pub const content_buf_size: usize = buffer_size - aes.nonce_length - aes.tag_length;

client: net.TcpClient,

back_buffer: [content_buf_size]u8 = undefined,
chunk_buffer: [content_buf_size]u8 = undefined,

fn pipeFile(self: *Transmitter, file: std.fs.File, key: [crypt.key_length]u8) PipeFileError!void {
    var encr_buf: [content_buf_size]u8 = undefined;
    var auth_tag_buf: [aes.tag_length]u8 = undefined;

    while (true) {
        const bytes_read = file.reader(&self.back_buffer).read(&self.chunk_buffer) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return PipeFileError.ReadFailed,
        };

        const nonce: [aes.nonce_length]u8 = undefined;
        std.crypto.random.bytes(nonce);
        try self.client.send(nonce);

        aes.encrypt(
            &encr_buf,
            &auth_tag_buf,
            self.chunk_buffer[0..bytes_read],
            &.{},
            nonce,
            key,
        );

        try self.client.send(encr_buf);
        try self.client.send(&auth_tag_buf);

        if (bytes_read < buffer_size) break;
    }
}

pub fn postFile(self: *Transmitter, file: std.fs.File) PostFileError!void {
    const stat = try file.stat();
    const data_size = stat.size + (stat.size / content_buf_size + 1) * (aes.nonce_length + aes.tag_length);
}

pub fn fetchManifest(self: Transmitter) []const u8 {
    _ = self;
    return "a8c22e46";
}

pub fn retrieveSalt(manifest: *[]const u8) []const u8 {
    const salt = manifest[0..crypt.salt_lenght];
    manifest = manifest[crypt.salt_lenght..];
    return salt;
}
