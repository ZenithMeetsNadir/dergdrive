const std = @import("std");
const builtin = @import("builtin");

const proj_name: []const u8 = "dergdrive";

pub const GetFileContentError = std.fs.File.OpenError || std.fs.File.StatError || std.mem.Allocator.Error || std.fs.File.ReadError;
pub const CreateConfFileError = std.fs.Dir.MakeError || std.fs.Dir.OpenError || std.fs.Dir.StatError || std.fs.File.OpenError || std.mem.Allocator.Error || std.fs.File.ChmodError;
pub const WriteConfFileError = CreateConfFileError || std.fs.File.WriteError;

fn getFileContent(path: []const u8, allocator: std.mem.Allocator) GetFileContentError![]const u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const stat = try file.stat();
    const buf = try allocator.alloc(u8, stat.size);
    errdefer allocator.free(buf);

    const bytes_read = try file.read(buf);

    std.debug.assert(stat.size == bytes_read);

    return buf;
}

const global_linux: []const u8 = "/etc/" ++ proj_name;
const local_linux: []const u8 = "~/.config/" ++ proj_name;
const secret_linux: []const u8 = local_linux ++ "/secret";
const internal: []const u8 = ".";

pub const LocNamespace = enum {
    global,
    local,
    internal,
    secret,

    pub fn getRoot(namespace: LocNamespace) []const u8 {
        return switch (builtin.os.tag) {
            .linux => switch (namespace) {
                .global => global_linux,
                .local => local_linux,
                .internal => internal,
                .secret => secret_linux,
            },
            else => @compileError("implement this for your os if you want it so bad"),
        };
    }
};

pub fn expandHomeDir(path: []const u8, allocator: std.mem.Allocator) std.mem.Allocator.Error![]const u8 {
    switch (builtin.os.tag) {
        .linux => {
            if (path.len > 0 and path[0] == '~') {
                var home = std.posix.getenv("HOME");
                if (home == null)
                    home = std.posix.getenv("USERPROFILE");

                if (home == null)
                    std.debug.panic("user home directory could not be inquired", .{});

                const slices: []const []const u8 = if (path.len > 2 and path[1] == '/') &.{ home.?, path[2..] } else &.{home.?};
                return std.mem.join(allocator, "/", slices);
            }
        },
        else => {},
    }

    return allocator.dupe(u8, path);
}

pub const ConfFile = struct {
    nspace: LocNamespace,
    sub_path: []const u8,

    pub fn getFullPath(self: ConfFile, allocator: std.mem.Allocator) std.mem.Allocator.Error![]const u8 {
        const root_path = self.nspace.getRoot();
        defer allocator.free(root_path);
        const expanded = try expandHomeDir(root_path, allocator);
        return std.mem.join(allocator, "/", &.{ expanded, self.sub_path });
    }
};

pub fn getConf(conf_file: ConfFile, allocator: std.mem.Allocator) GetFileContentError![]const u8 {
    const full_path = try conf_file.getFullPath(allocator);
    defer allocator.free(full_path);

    return getFileContent(full_path, allocator);
}

pub fn createConfFile(conf_file: ConfFile, truncate: bool, allocator: std.mem.Allocator) CreateConfFileError!std.fs.File {
    const full_path = try conf_file.getFullPath(allocator);
    defer allocator.free(full_path);

    const last_slash = std.mem.lastIndexOfScalar(u8, full_path, '/');
    const dir_path = full_path[0 .. last_slash orelse 0];

    const file_delim = if (last_slash) |pos| pos + 1 else 0;
    const file_path = full_path[file_delim..];

    var dir = try std.fs.cwd().makeOpenPath(dir_path, .{});
    errdefer dir.close();

    const file = try dir.createFile(file_path, .{ .read = true, .truncate = truncate });
    errdefer file.close();

    if (conf_file.nspace == .secret)
        try file.chmod(0o600);

    return file;
}

pub fn writeConfFile(conf_file: ConfFile, truncate: bool, data: []const u8, allocator: std.mem.Allocator) WriteConfFileError!void {
    const file = try createConfFile(conf_file, truncate, allocator);
    errdefer file.close();

    const bytes_written = try file.write(data);
    std.debug.assert(bytes_written == data.len);
}
