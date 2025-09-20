const std = @import("std");
const builtin = @import("builtin");

const proj_name: []const u8 = "dergdrive";

const GetFileContentError = std.fs.File.OpenError || std.fs.File.StatError || std.mem.Allocator.Error || std.fs.File.ReadError;
const CreateConfFileError = std.fs.Dir.MakeError || std.fs.Dir.OpenError || std.fs.Dir.StatError || std.fs.File.OpenError || std.mem.Allocator.Error;

fn getFileContent(path: []const u8, allocator: std.mem.Allocator) GetFileContentError![]const u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const stat = try file.stat();
    const buf = try allocator.alloc(u8, stat.size);
    const bytes_read = file.read(buf);

    std.debug.assert(stat.size == bytes_read);

    return buf;
}

pub const LocNamespace = enum {
    global,
    local,
    internal,
};

const global_linux: []const u8 = "/etc/" ++ proj_name;
const local_linux: []const u8 = "~/.config/" ++ proj_name;
const internal: []const u8 = ".";

fn getNamespaceRoot(namespace: LocNamespace) []const u8 {
    return switch (builtin.os.tag) {
        .linux => switch (namespace) {
            .global => global_linux,
            .local => local_linux,
            .internal => internal,
        },
        else => @compileError("implement this for your os if you want it so bad"),
    };
}

pub fn getFileContentNamespaced(namespace: LocNamespace, sub_path: []const u8, allocator: std.mem.Allocator) GetFileContentError![]const u8 {
    const full_path = try std.mem.join(allocator, "/", &.{ getNamespaceRoot(namespace), sub_path });
    defer allocator.free(full_path);

    return getFileContent(full_path, allocator);
}

fn createConfFile(namespace: LocNamespace, sub_path: []const u8, allocator: std.mem.Allocator) CreateConfFileError!std.fs.File {
    const full_path = try std.mem.join(allocator, "/", &.{ getNamespaceRoot(namespace), sub_path });
    defer allocator.free(full_path);

    const last_slash = std.mem.lastIndexOfScalar(u8, full_path, '/');
    const dir_path = full_path[0 .. last_slash orelse 0];

    const file_delim = if (last_slash) last_slash + 1 else 0;
    const file_path = full_path[file_delim..];

    const dir = try std.fs.cwd().makeOpenPath(dir_path, .{});
    return try dir.createFile(file_path, .{});
}
