const std = @import("std");
const expect = std.testing.expect;

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var dir = try std.fs.openDirAbsolute("/home/vlcaak", .{ .iterate = true });
    defer dir.close();

    const rule_text = @embedFile("./include");

    var tree = IncludeTree.init(dir, rule_text, allocator);
    defer tree.deinit();

    try tree.buildGraph();
    for (tree.flat_tree.items) |item| {
        switch (item) {
            .file => |file| std.debug.print("file: {s}\n", .{file}),
            .dir => |dir_node| std.debug.print("dir: {s} (breadth: {d})\n", .{ dir_node.name, dir_node.flat_breadth }),
        }
    }
}

pub const FileNode = []const u8;

pub const DirNode = struct {
    name: []const u8,
    flat_breadth: usize,
};

pub const TreeNode = union(enum) {
    file: FileNode,
    dir: DirNode,
};

pub const IncludeTree = struct {
    const capacity_exp = 16;

    const RuleIterator = struct {
        iterator: std.mem.SplitIterator(u8, .any),

        pub fn init(text: []const u8) RuleIterator {
            return .{ .iterator = std.mem.splitAny(u8, text, "\r\n") };
        }

        pub fn next(self: *RuleIterator) ?[]const u8 {
            return while (self.iterator.next()) |item| {
                const trimmed = std.mem.trim(u8, item, " \t");
                if (trimmed.len == 0 or trimmed[0] == '#')
                    continue;

                break trimmed;
            } else null;
        }
    };

    const MatchingIterator = struct {
        path: []const u8,
        is_dir: bool,
        rules: RuleIterator,

        pub fn init(path: []const u8, is_dir: bool, rules: RuleIterator) MatchingIterator {
            return .{ .path = path, .is_dir = is_dir, .rules = rules };
        }

        pub fn next(self: *MatchingIterator) ?[]const u8 {
            const rule = self.rules.next() orelse return null;
            return if (match(self.path, self.is_dir, rule)) rule else null;
        }

        pub fn peek(self: MatchingIterator) ?[]const u8 {
            var copy = self;
            return copy.next();
        }
    };

    flat_tree: std.ArrayList(TreeNode) = .empty,
    allocator: std.mem.Allocator,
    root_dir: std.fs.Dir,
    rules: RuleIterator,
    level: usize = 0,

    pub fn init(root_dir: std.fs.Dir, rule_text: []const u8, allocator: std.mem.Allocator) IncludeTree {
        return .{ .allocator = allocator, .root_dir = root_dir, .rules = .init(rule_text) };
    }

    pub fn deinit(self: *IncludeTree) void {
        for (self.flat_tree.items) |item| {
            switch (item) {
                .file => |file| self.allocator.free(file),
                .dir => |dir| self.allocator.free(dir.name),
            }
        }

        self.flat_tree.deinit(self.allocator);
    }

    fn addNode(self: *IncludeTree, node: TreeNode) std.mem.Allocator.Error!void {
        if (self.flat_tree.items.len == self.flat_tree.capacity)
            try self.flat_tree.ensureTotalCapacity(self.allocator, self.flat_tree.capacity + capacity_exp);

        self.flat_tree.appendAssumeCapacity(node);
    }

    pub fn buildGraph(self: *IncludeTree) !void {
        _ = try self.iterateDir(self.root_dir, self.rules, 1, "");
    }

    fn iterateDir(self: *IncludeTree, dir: std.fs.Dir, rule_iter: RuleIterator, level: usize, path: []const u8) !usize {
        var num_nodes_added: usize = 0;
        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            const path_chunks: []const []const u8 = if (path.len == 0) &.{entry.name} else &.{ path, entry.name };
            // free if not added as a node
            const full_path = try std.mem.join(self.allocator, "/", path_chunks);

            std.debug.print("full_path: {s}\n", .{full_path});

            var match_iter: MatchingIterator = .init(full_path, entry.kind == .directory, rule_iter);
            var prio_rule: ?[]const u8 = null;

            while (match_iter.peek() != null)
                prio_rule = match_iter.next() orelse unreachable;

            if (prio_rule) |rule| std.debug.print("matched rule: {s}\n", .{rule});

            var node_index: ?usize = null;
            var node_added = false;
            if (prio_rule) |rule_match| {
                if (ignore(rule_match) == levelIsIgnore(level)) {
                    num_nodes_added += 1;
                    node_added = true;

                    switch (entry.kind) {
                        .file => try self.addNode(.{ .file = full_path }),
                        .directory => {
                            try self.addNode(.{ .dir = .{ .name = full_path, .flat_breadth = 0 } });
                            node_index = self.flat_tree.items.len - 1;
                        },
                        else => node_added = false,
                    }
                }
            }

            if (entry.kind == .directory) {
                const level_inc: usize = if (node_added) 1 else 0;
                if (searchForChildRules(full_path, rule_iter, level + level_inc)) {
                    var child_dir = try dir.openDir(entry.name, .{ .iterate = true });
                    defer child_dir.close();

                    const child_dir_nodes = try self.iterateDir(child_dir, match_iter.rules, level + level_inc, full_path);

                    if (node_index) |index| {
                        switch (self.flat_tree.items[index]) {
                            .dir => |*dir_node| dir_node.flat_breadth += child_dir_nodes,
                            else => unreachable,
                        }
                    }

                    num_nodes_added += child_dir_nodes;
                }
            }

            if (!node_added)
                self.allocator.free(full_path);
        }

        return num_nodes_added;
    }

    inline fn ignore(rule: []const u8) bool {
        return rule.len > 0 and rule[0] == '!';
    }

    inline fn levelIsIgnore(level: usize) bool {
        return level % 2 == 0;
    }

    fn searchForChildRules(parent_path: []const u8, rule_iter: RuleIterator, level: usize) bool {
        var iter = rule_iter;
        return while (iter.next()) |rule| {
            if (canHaveChild(parent_path, rule, level)) {
                std.debug.print("found child rule: {s}\n", .{rule});
                break true;
            }
        } else false;
    }

    fn canHaveChild(parent_path: []const u8, rule: []const u8, level: usize) bool {
        if (levelIsIgnore(level) != ignore(rule))
            return false;

        if (canMatchAnywhere(rule))
            return true;

        var rule_mut = rule;
        var rule_slashes = std.mem.count(u8, rule_mut, "/");
        const parent_slashes = std.mem.count(u8, parent_path, "/");
        const double_ast = std.mem.indexOf(u8, rule_mut, "**") != null;

        return while (rule_mut.len > 0 and (rule_slashes >= parent_slashes or double_ast)) : ({
            const slash_end = std.mem.lastIndexOfScalar(u8, rule_mut, '/') orelse 0;
            rule_mut = rule_mut[0..slash_end];
            rule_slashes -|= 1;
        }) {
            if (match(parent_path, true, rule_mut))
                break true;
        } else false;
    }

    fn match(path: []const u8, is_dir: bool, rule: []const u8) bool {
        if (rule.len < 1)
            return false;

        var rule_mut = std.mem.trimStart(u8, rule, "!");
        if (rule_mut.len < 1)
            return false;

        if (rule_mut[rule_mut.len - 1] == '/' and !is_dir)
            return false;

        const match_end = canMatchAnywhere(rule_mut);

        rule_mut = std.mem.trim(u8, rule_mut, "/");
        if (rule_mut.len < 1)
            return false;

        var rule_iter = std.mem.splitScalar(u8, rule_mut, '*');
        var path_pos: usize = if (match_end) blk: {
            if (std.mem.lastIndexOfScalar(u8, path, '/')) |pos| break :blk pos + 1 else break :blk 0;
        } else 0;

        var rule_chunk_matched = false;
        return while (rule_iter.next()) |rule_chunk| {
            var rule_chunk_mut = rule_chunk;
            const peek_rule = rule_iter.peek();

            if (rule_chunk_mut.len == 0) {
                if (rule_iter.index != 1 and peek_rule != null) {
                    var next_rule = peek_rule orelse unreachable;
                    if (next_rule.len == 0) {
                        if (path_pos == 0)
                            break true;

                        break path[path_pos - 1] == '/';
                    }

                    if (!matchRuleChunk(path, &path_pos, &next_rule, false))
                        break false;

                    rule_chunk_matched = true;
                    continue;
                }
            } else if (!rule_chunk_matched) {
                if (!matchRuleChunk(path, &path_pos, &rule_chunk_mut, true))
                    break false;
            }

            rule_chunk_matched = false;

            if (peek_rule) |peek| {
                if (peek.len > 0) {
                    const next_slash = std.mem.indexOfPos(u8, path, path_pos, "/");

                    if (peek[0] == '/') {
                        if (next_slash) |pos| {
                            path_pos = pos + 1;
                        } else break false;
                    } else {
                        var next_rule = peek;
                        const max_pos = next_slash orelse path.len;

                        if (!matchRuleChunk(path, &path_pos, &next_rule, false) or path_pos - next_rule.len >= max_pos)
                            break false;

                        rule_chunk_matched = true;
                    }
                } else if (rule_iter.index == rule_mut.len) {
                    if (rule_chunk.len > 0 and rule_chunk[rule_chunk.len - 1] == '/' and path[path_pos - 1] != '/')
                        break false;

                    path_pos = path.len;
                }
            }
        } else path_pos == path.len;
    }

    fn canMatchAnywhere(rule: []const u8) bool {
        const slash_pos = std.mem.indexOfScalar(u8, rule, '/');
        return slash_pos == null or slash_pos == rule.len - 1;
    }

    fn matchRuleChunk(path: []const u8, path_pos: *usize, rule_chunk: *[]const u8, strict: bool) bool {
        rule_chunk.* = std.mem.trim(u8, rule_chunk.*, "/");
        path_pos.* = if (std.mem.indexOfPos(u8, path, path_pos.*, rule_chunk.*)) |pos| blk: {
            if (strict and pos != path_pos.*)
                return false;

            break :blk pos + rule_chunk.len;
        } else return false;

        if (path_pos.* + 1 < path.len and path[path_pos.*] == '/')
            path_pos.* += 1;

        return true;
    }
};

test "match path chunk" {
    const path = "foo/owo/bar";
    var path_pos: usize = 0;
    var rule: []const u8 = "foo/";
    try expect(IncludeTree.matchRuleChunk(path, &path_pos, &rule, false));
    rule = "/bar";
    try expect(IncludeTree.matchRuleChunk(path, &path_pos, &rule, false));
    try expect(path_pos == path.len);
}

test "match path anywhere" {
    try expect(IncludeTree.match("foo", false, "foo"));
    try expect(IncludeTree.match("foo", false, "/foo"));
    try expect(!IncludeTree.match("foo", false, "/foo/"));
    try expect(IncludeTree.match("foo", true, "/foo/"));

    try expect(IncludeTree.match("foo/bar", false, "bar"));
    try expect(IncludeTree.match("foo/owo/bar", false, "bar"));
    try expect(!IncludeTree.match("foo/owo/bar", false, "owo"));
    try expect(!IncludeTree.match("foo/owo/bar", false, "foo"));
    try expect(!IncludeTree.match("foo/bar", false, "bar/"));
    try expect(IncludeTree.match("foo/owo/bar", true, "bar/"));
    try expect(!IncludeTree.match("foo/owo/bar", false, "owo/bar"));
}

test "match single ast wildcard" {
    try expect(IncludeTree.match("owo", false, "*"));
    try expect(!IncludeTree.match("owo", false, "*/"));
    try expect(IncludeTree.match("owo", true, "*/"));
    try expect(IncludeTree.match("foo.txt", false, "foo.*"));
    try expect(IncludeTree.match("foo.exe", false, "foo.*"));
    try expect(IncludeTree.match("foo.txt", false, "*.txt"));
    try expect(IncludeTree.match("bar.txt", false, "*.txt"));
    try expect(IncludeTree.match("foo/owo/bar", false, "foo/*/bar"));
    try expect(IncludeTree.match("foo/owo/bar", false, "foo/*wo/bar"));
    try expect(IncludeTree.match("foo/owo/bar", false, "foo/o*/bar"));
    try expect(!IncludeTree.match("foo/owo/bar", false, "foo/*ar"));
    try expect(!IncludeTree.match("foo", false, "foo/*"));
    try expect(IncludeTree.match("foo/bar", false, "foo/*"));

    // matches the first occurence of the rule chunk after wildcard
    try expect(!IncludeTree.match("foo", false, "f*o"));
    try expect(IncludeTree.match("foo/owo/bar", false, "f*o/ow*/bar"));
    try expect(IncludeTree.match("foo/owo/bar", false, "foo/*w*/bar"));
    try expect(!IncludeTree.match("foo", false, "foo/**"));
}

test "match double ast wildcard" {
    try expect(IncludeTree.match("foo/owo/bar", true, "foo/owo/**/"));
    try expect(IncludeTree.match("foo/owo/bar", true, "foo/**/bar/"));
    try expect(IncludeTree.match("foo/owo/bar", true, "**/owo/bar/"));
}

test "can have child" {
    try expect(IncludeTree.canHaveChild("foo", "bar", 1));
    try expect(!IncludeTree.canHaveChild("foo", "bar", 2));
    try expect(IncludeTree.canHaveChild("foo", "foo/bar/", 1));
    try expect(IncludeTree.canHaveChild("foo", "**/", 1));
    try expect(IncludeTree.canHaveChild("foo", "**/owo", 1));
    try expect(!IncludeTree.canHaveChild("foo", "bar/**/owo", 1));
    try expect(IncludeTree.canHaveChild("foo", "foo/**/owo", 1));
    try expect(IncludeTree.canHaveChild("foo", "*/owo", 1));
    try expect(!IncludeTree.canHaveChild("foo/bar/baz", "*/owo", 1));
}
