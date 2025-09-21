const std = @import("std");
const net = @import("net");
const root = @import("dergdrive");
const proto = root.proto;
const crypt = root.crypt;
const aes = crypt.aes;
const conf = root.conf;
const cli = root.cli;

const Transmitter = @This();

pub const PipeFileError = net.TcpClient.SendError || error{ReadFailed};
pub const PostFileError = PipeFileError || std.fs.File.StatError;
pub const FetchManifestError = error{};
pub const GetKeyError = error{
    ManifestFormatInvalid,
    Timeout,
};

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
    _ = self;
    const stat = try file.stat();
    const data_size = stat.size + (stat.size / content_buf_size + 1) * (aes.nonce_length + aes.tag_length);
    _ = data_size;
}

pub fn fetchManifest(self: Transmitter, allocator: std.mem.Allocator) FetchManifestError![]const u8 {
    _ = self;
    _ = allocator;
    return "a8c22e46";
}

fn retrieveSalt(manifest: []const u8) []const u8 {
    return manifest[0..crypt.salt_length];
}

fn getKey(self: Transmitter, allocator: std.mem.Allocator) GetKeyError![crypt.key_length]u8 {
    if (conf.getConf(.secret, crypt.key_path, allocator)) |key| {
        std.log.info("cached key: {}", .{key});
        if (key.len == crypt.key_length)
            return key;
    }

    std.log.info("key not cached, fetching manifest", .{});

    // TODO make this fetch async
    const manifest = try self.fetchManifest(allocator);
    const salt = retrieveSalt(manifest);

    const passw = try cli.prompt.promptUser("enter password for {s}", .{"user"}, allocator);
}
