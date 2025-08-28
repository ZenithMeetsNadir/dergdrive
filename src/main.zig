const std = @import("std");
const dergdrive = @import("dergdrive");
const net = @import("net");

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var server = try net.TcpServer.open("0.0.0.0", 9999, true, allocator);
    defer server.close();

    server.dispatch_fn = serverDispatch;
    try server.listen();

    var client = try net.TcpClient.connect("127.0.0.1", 9999, true);
    defer client.close();

    client.dispatch_fn = clientDispatch;
    try client.listen();

    try client.send("Hello from client!\n");

    std.Thread.sleep(std.time.ns_per_s * 4);
}

fn serverDispatch(connection: *net.TcpServer.Connection, data: []const u8) anyerror!void {
    std.debug.print("Server received: {s}\n", .{data});

    try connection.send(data);
}

fn clientDispatch(client: *const net.TcpClient, data: []const u8) anyerror!void {
    _ = client;
    std.debug.print("Client received: {s}\n", .{data});
}
