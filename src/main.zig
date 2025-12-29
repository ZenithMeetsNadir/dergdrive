const std = @import("std");
const dergdrive = @import("dergdrive");
const znetw = @import("znetw");

const buffer_size = 0x20000; // 128 kB
var reader_buf: [buffer_size]u8 = undefined;

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var server = try znetw.TcpServer.open("0.0.0.0", 9999, true, buffer_size, allocator);
    defer server.close();

    server.dispatch_fn = serverDispatch;
    try server.listen();

    var client = try znetw.TcpClient.connect("127.0.0.1", 9999, true, buffer_size);
    defer client.close();

    client.dispatch_fn = clientDispatch;
    try client.listen(allocator);

    const file = try std.fs.openFileAbsolute("/home/vlcaak/srccode/zig/dergdrive/test.flac", .{});
    defer file.close();
    var reader = file.reader(&reader_buf);

    const size = try reader.getSize();
    std.log.info("file size: {d}", .{size});

    var buffer: [buffer_size]u8 = undefined;
    var bytes_read: usize = 0;

    while (true) {
        bytes_read = reader.read(&buffer) catch break;
        if (bytes_read == 0) break;

        try client.send(buffer[0..bytes_read]);
    }

    std.Thread.sleep(std.time.ns_per_s * 4);

    if (server_file) |f| {
        f.close();
    }
}

var server_file: ?std.fs.File = null;
var writer_buf: [buffer_size]u8 = undefined;

fn serverDispatch(connection: *znetw.TcpServer.Connection, data: []const u8) anyerror!void {
    _ = connection;

    if (server_file == null)
        server_file = try std.fs.cwd().createFile("received.flac", .{ .truncate = false });

    const bytes_written = try server_file.?.write(data);
    std.log.info("server wrote {d} bytes of {d}", .{ bytes_written, data.len });
}

fn clientDispatch(client: *const znetw.TcpClient, data: []const u8) anyerror!void {
    _ = client;
    std.debug.print("Client received: {s}\n", .{data});
}
