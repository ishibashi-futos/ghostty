const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const ascii = std.ascii;
const testing = std.testing;

/// Search for "cmd" in the PATH and return the absolute path. This will
/// always allocate if there is a non-null result. The caller must free the
/// resulting value.
pub fn expand(alloc: Allocator, cmd: []const u8) !?[]u8 {
    // If the command already contains a slash, then we return it as-is
    // because it is assumed to be absolute or relative.
    if (hasPathSeparator(cmd)) {
        return try alloc.dupe(u8, cmd);
    }

    const PATH = switch (builtin.os.tag) {
        .windows => blk: {
            const win_path = std.process.getenvW(std.unicode.utf8ToUtf16LeStringLiteral("PATH")) orelse return null;
            const path = try std.unicode.utf16LeToUtf8Alloc(alloc, win_path);
            break :blk path;
        },
        else => std.posix.getenvZ("PATH") orelse return null,
    };
    defer if (builtin.os.tag == .windows) alloc.free(PATH);

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cmd_has_ext = if (builtin.os.tag == .windows) windowsHasExtension(cmd) else true;
    const pathext = if (builtin.os.tag == .windows and !cmd_has_ext)
        try windowsPathext(alloc)
    else
        null;
    defer if (pathext) |v| alloc.free(v);
    const pathext_value = pathext orelse ".COM;.EXE;.BAT;.CMD";

    var it = std.mem.tokenizeScalar(u8, PATH, std.fs.path.delimiter);
    var seen_eacces = false;
    while (it.next()) |search_path| {
        if (builtin.os.tag == .windows and !cmd_has_ext) {
            var ext_it = std.mem.tokenizeScalar(u8, pathext_value, ';');
            while (ext_it.next()) |ext_raw| {
                if (ext_raw.len == 0) continue;
                const ext_needs_dot = ext_raw[0] != '.';
                const ext_len = ext_raw.len + @intFromBool(ext_needs_dot);

                const path_len = search_path.len + cmd.len + ext_len + 1;
                if (path_buf.len < path_len) return error.PathTooLong;

                @memcpy(path_buf[0..search_path.len], search_path);
                path_buf[search_path.len] = std.fs.path.sep;
                @memcpy(path_buf[search_path.len + 1 ..][0..cmd.len], cmd);
                if (ext_needs_dot) {
                    path_buf[search_path.len + 1 + cmd.len] = '.';
                    @memcpy(
                        path_buf[search_path.len + 1 + cmd.len + 1 ..][0..ext_raw.len],
                        ext_raw,
                    );
                } else {
                    @memcpy(
                        path_buf[search_path.len + 1 + cmd.len ..][0..ext_raw.len],
                        ext_raw,
                    );
                }
                path_buf[path_len] = 0;
                const full_path = path_buf[0..path_len :0];

                const found = try checkExecutable(full_path, &seen_eacces);
                if (found) return try alloc.dupe(u8, full_path);
            }
        } else {
            const path_len = search_path.len + cmd.len + 1;
            if (path_buf.len < path_len) return error.PathTooLong;

            @memcpy(path_buf[0..search_path.len], search_path);
            path_buf[search_path.len] = std.fs.path.sep;
            @memcpy(path_buf[search_path.len + 1 ..][0..cmd.len], cmd);
            path_buf[path_len] = 0;
            const full_path = path_buf[0..path_len :0];

            const found = try checkExecutable(full_path, &seen_eacces);
            if (found) return try alloc.dupe(u8, full_path);
        }
    }

    if (seen_eacces) return error.AccessDenied;

    return null;
}

fn checkExecutable(full_path: [:0]const u8, seen_eacces: *bool) !bool {
    const f = std.fs.cwd().openFile(
        full_path,
        .{},
    ) catch |err| switch (err) {
        error.FileNotFound => return false,
        error.AccessDenied => {
            seen_eacces.* = true;
            return false;
        },
        else => return err,
    };
    defer f.close();
    const stat = try f.stat();
    return stat.kind != .directory and isExecutable(stat.mode);
}

fn isExecutable(mode: std.fs.File.Mode) bool {
    if (builtin.os.tag == .windows) return true;
    return mode & 0o0111 != 0;
}

fn hasPathSeparator(cmd: []const u8) bool {
    if (builtin.os.tag == .windows) {
        if (std.mem.indexOfAny(u8, cmd, "/\\") != null) return true;
        return cmd.len >= 2 and cmd[1] == ':' and ascii.isAlphabetic(cmd[0]);
    }

    return std.mem.indexOfScalar(u8, cmd, '/') != null;
}

fn windowsHasExtension(cmd: []const u8) bool {
    const base = std.fs.path.basename(cmd);
    return std.mem.indexOfScalar(u8, base, '.') != null;
}

fn windowsPathext(alloc: Allocator) ![]u8 {
    const pathext = std.process.getEnvVarOwned(alloc, "PATHEXT") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return try alloc.dupe(u8, ".COM;.EXE;.BAT;.CMD"),
        error.InvalidWtf8 => return try alloc.dupe(u8, ".COM;.EXE;.BAT;.CMD"),
        else => return err,
    };
    if (pathext.len == 0) {
        alloc.free(pathext);
        return try alloc.dupe(u8, ".COM;.EXE;.BAT;.CMD");
    }
    return pathext;
}

// `uname -n` is the *nix equivalent of `hostname.exe` on Windows
test "expand: hostname" {
    const executable = if (builtin.os.tag == .windows) "hostname.exe" else "uname";
    const path = (try expand(testing.allocator, executable)).?;
    defer testing.allocator.free(path);
    try testing.expect(path.len > executable.len);
}

test "expand: does not exist" {
    const path = try expand(testing.allocator, "thisreallyprobablydoesntexist123");
    try testing.expect(path == null);
}

test "expand: slash" {
    const path = (try expand(testing.allocator, "foo/env")).?;
    defer testing.allocator.free(path);
    try testing.expect(path.len == 7);
}
