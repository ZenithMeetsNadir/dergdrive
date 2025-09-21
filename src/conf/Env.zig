const std = @import("std");
const conf = @import("conf.zig");

const Env = @This();

const KeyValueIterator = struct {
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
    ) (std.mem.Allocator.Error || std.fs.File.StatError || std.fs.File.ReadError)!KeyValueIterator {
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

    pub fn refresh(self: *KeyValueIterator) (std.mem.Allocator.Error || std.fs.File.StatError || std.fs.File.ReadError)!void {
        self.deinit();
        self = try .init(self.allocator, self.env_file);
    }

    pub fn next(self: *KeyValueIterator) ?KVPair {
        return while (self.line_iter.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t");
            if (trimmed.len > 0 and trimmed[0] != '#') {
                if (std.mem.indexOfScalar(u8, trimmed, kv_delim)) |delim| {
                    return .{
                        .key = std.mem.slice(trimmed, 0, delim),
                        .value = std.mem.slice(trimmed, delim + 1, trimmed.len),
                    };
                }
            }
        } else null;
    }
};

pub const GetIteratorError = std.mem.Allocator.Error || conf.CreateConfFileError;

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
    for (iter.next()) |entry| {
        entry.value_ptr.env_file.close();
        entry.value_ptr.deinit();
    }

    self.loaded_envs.deinit();
}

fn getIteratorPtr(self: *Env, env_file: conf.ConfFile) GetIteratorError!*KeyValueIterator {
    const full_path = try env_file.getFullPath(self.allocator);
    defer self.allocator.free(full_path);

    const res = try self.loaded_envs.getOrPut(full_path);
    if (!res.found_existing)
        res.value_ptr.* = .init(self.allocator, try conf.createConfFile(env_file, true, self.allocator));

    return res.value_ptr;
}

pub fn get(self: *Env, env_file: conf.ConfFile, key: []const u8) GetIteratorError!?KeyValueIterator {
    const iter = try self.getIteratorPtr(env_file);
    iter.line_iter.index = 0;
    return while (iter.next()) |entry| {
        if (std.mem.eql(u8, entry.key, key))
            break entry.value;
    } else null;
}

pub fn set(self: *Env, env_file: conf.ConfFile, key: []const u8, value: []const u8) (GetIteratorError || std.fs.File.WriteError)!void {
    const iter = try self.getIteratorPtr(env_file);
    iter.line_iter.index = 0;

    var key_len: usize = 0;
    var val_len: usize = 0;
    var index: usize = 0;
    const insert = while (iter.next()) |entry| : (index = iter.line_iter.index) {
        if (std.mem.eql(u8, entry.key, key)) {
            key_len = entry.value.len;
            val_len = entry.value.len;
            break true;
        }
    } else false;

    if (insert) {
        const tail_index = index + key_len + val_len + 1;
        const len_diff = value.len - val_len;
        const new_len = iter.line_iter.buffer.len + len_diff;
        const new_buf = try iter.allocator.realloc(iter.line_iter.buffer, new_len);

        @memmove(new_buf[tail_index + len_diff ..], new_buf[tail_index .. new_buf.len - len_diff]);
        @memcpy(new_buf[index + key_len + 1 ..], value);

        iter.line_iter.buffer = new_buf;
    } else {
        const old_len = iter.line_iter.buffer.len;
        const new_len = old_len + key.len + value.len + 1;
        const new_buf = try iter.allocator.realloc(iter.line_iter.buffer, new_len);

        @memcpy(new_buf[old_len .. old_len + key.len], key);
        new_buf[old_len + key.len] = kv_delim;
        @memcpy(new_buf[old_len + key.len + 1 ..], value);

        iter.line_iter.buffer = new_buf;
    }

    try iter.env_file.write(iter.line_iter.buffer);
}
