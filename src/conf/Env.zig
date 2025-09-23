const std = @import("std");
const conf = @import("conf.zig");

const Env = @This();

const KeyValueIterator = struct {
    pub const InitError = std.mem.Allocator.Error || std.fs.File.StatError || std.fs.File.ReadError;

    pub const KVPair = struct {
        key: []const u8,
        value: []const u8,
    };

    env_file: std.fs.File,
    line_iter: std.mem.SplitIterator(u8, .any),
    allocator: std.mem.Allocator,

    pub fn init(
        allocator: std.mem.Allocator,
        env_file: std.fs.File,
    ) InitError!KeyValueIterator {
        const stat = try env_file.stat();
        const buf = try allocator.alloc(u8, stat.size);

        const bytes_read = try env_file.read(buf);
        std.debug.assert(bytes_read == stat.size);

        return .{
            .env_file = env_file,
            .line_iter = std.mem.splitAny(u8, buf, "\r\n"),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: KeyValueIterator) void {
        self.allocator.free(self.line_iter.buffer);
    }

    pub fn refresh(self: *KeyValueIterator) InitError!void {
        self.deinit();
        self = try .init(self.allocator, self.env_file);
    }

    pub fn next(self: *KeyValueIterator) ?KVPair {
        return while (self.line_iter.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t");
            if (trimmed.len > 0 and trimmed[0] != '#') {
                if (std.mem.indexOfScalar(u8, trimmed, kv_delim)) |delim| {
                    return .{
                        .key = line[0..delim],
                        .value = line[delim + 1 ..],
                    };
                }
            }
        } else null;
    }
};

pub const GetIteratorError = std.mem.Allocator.Error || conf.CreateConfFileError || KeyValueIterator.InitError;

pub var env: Env = undefined;

pub const kv_delim: u8 = '=';

loaded_envs: std.StringHashMap(KeyValueIterator),
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) Env {
    return Env{
        .loaded_envs = .init(allocator),
        .allocator = allocator,
    };
}

pub fn deinit(self: *Env) void {
    var iter = self.loaded_envs.iterator();
    while (iter.next()) |entry| {
        entry.value_ptr.env_file.close();
        entry.value_ptr.deinit();
        self.allocator.free(entry.key_ptr.*);
    }

    self.loaded_envs.deinit();
}

fn getIteratorPtr(self: *Env, env_file: conf.ConfFile) GetIteratorError!*KeyValueIterator {
    const full_path = try env_file.getFullPath(self.allocator);

    const res = try self.loaded_envs.getOrPut(full_path);
    if (!res.found_existing) {
        const file = try conf.createConfFile(env_file, true, self.allocator);
        errdefer file.close();

        res.value_ptr.* = try .init(self.allocator, file);
    }

    if (res.found_existing)
        self.allocator.free(full_path);

    return res.value_ptr;
}

fn refreshIterFile(self: *Env, iter: *KeyValueIterator, env_file: conf.ConfFile) GetIteratorError!void {
    iter.env_file.close();
    iter.env_file = try conf.createConfFile(env_file, true, self.allocator);
}

pub fn get(self: *Env, env_file: conf.ConfFile, key: []const u8) GetIteratorError!?[]const u8 {
    const iter = try self.getIteratorPtr(env_file);
    iter.line_iter.index = 0;
    return while (iter.next()) |entry| {
        if (std.mem.eql(u8, entry.key, key))
            break entry.value;
    } else null;
}

pub fn set(self: *Env, env_file: conf.ConfFile, key: []const u8, value: []const u8) (GetIteratorError || std.fs.File.WriteError)!void {
    var iter = try self.getIteratorPtr(env_file);
    try self.refreshIterFile(iter, env_file);
    iter.line_iter.index = 0;

    var key_len: usize = 0;
    var val_len: usize = 0;
    var index: usize = 0;
    const insert = while (iter.next()) |entry| : ({
        if (iter.line_iter.index) |i|
            index = i;
    }) {
        if (std.mem.eql(u8, entry.key, key)) {
            key_len = entry.key.len;
            val_len = entry.value.len;
            break true;
        }
    } else false;

    var buf: []u8 = @constCast(iter.line_iter.buffer);

    if (insert) {
        const tail_index = index + key_len + val_len + 1;
        const len_diff: isize = @bitCast(value.len -% val_len);
        const old_len = buf.len;
        const new_len: usize = @bitCast(@as(isize, @bitCast(buf.len)) + len_diff);

        // move before resizing if the new length is smaller to avoid clipping
        if (new_len < buf.len)
            @memmove(buf[@bitCast(@as(isize, @bitCast(tail_index)) + len_diff)..new_len], buf[tail_index..]);

        buf = try iter.allocator.realloc(buf, new_len);

        if (new_len >= old_len)
            @memmove(buf[@bitCast(@as(isize, @bitCast(tail_index)) + len_diff)..], buf[tail_index..old_len]);

        const value_index = index + key_len + 1;
        @memcpy(buf[value_index .. value_index + value.len], value);
    } else {
        var old_len = buf.len;
        const line_break = old_len != 0 and buf[old_len - 1] == '\n' or old_len == 0;

        if (!line_break)
            old_len += 1;

        const new_len = old_len + key.len + value.len + 1;
        buf = try iter.allocator.realloc(buf, new_len);

        if (!line_break)
            buf[old_len - 1] = '\n';

        @memcpy(buf[old_len .. old_len + key.len], key);
        buf[old_len + key.len] = kv_delim;
        @memcpy(buf[old_len + key.len + 1 ..], value);
    }

    iter.line_iter.buffer = buf;
    const bytes_written = try iter.env_file.write(buf);
    std.debug.assert(bytes_written == buf.len);
}

test "env" {
    env = .init(std.testing.allocator);
    defer env.deinit();

    const test_file: conf.ConfFile = .{
        .nspace = .local,
        .sub_path = "test.env",
    };

    try env.set(test_file, "key1", "owo");
    try env.set(test_file, "key2", "bar");
    try env.set(test_file, "key1", "foooo");

    var val1 = try env.get(test_file, "key1");
    try std.testing.expect(std.mem.eql(u8, val1.?, "foooo"));

    try env.set(test_file, "key1", "owo");

    val1 = try env.get(test_file, "key1");
    try std.testing.expect(std.mem.eql(u8, val1.?, "owo"));
}
