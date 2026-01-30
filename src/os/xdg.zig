//! Implementation of the XDG Base Directory specification
//! (https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html)

const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const posix = std.posix;
const homedir = @import("homedir.zig");
const env_os = @import("env.zig");

pub const Options = struct {
    /// Subdirectories to join to the base. This avoids extra allocations
    /// when building up the directory. This is commonly the application.
    subdir: ?[]const u8 = null,

    /// The home directory for the user. If this is not set, we will attempt
    /// to look it up which is an expensive process. By setting this, you can
    /// avoid lookups.
    home: ?[]const u8 = null,
};

/// Get the XDG user config directory. The returned value is allocated.
pub fn config(alloc: Allocator, opts: Options) ![]u8 {
    return try dir(alloc, opts, .{
        .env = "XDG_CONFIG_HOME",
        .windows_env = "LOCALAPPDATA",
        .windows_env_fallback = "APPDATA",
        .default_subdir = ".config",
        .windows_home_subdir = "AppData\\Local",
    });
}

/// Get the XDG cache directory. The returned value is allocated.
pub fn cache(alloc: Allocator, opts: Options) ![]u8 {
    return try dir(alloc, opts, .{
        .env = "XDG_CACHE_HOME",
        .windows_env = "LOCALAPPDATA",
        .default_subdir = ".cache",
        .windows_home_subdir = "AppData\\Local",
    });
}

/// Get the XDG state directory. The returned value is allocated.
pub fn state(alloc: Allocator, opts: Options) ![]u8 {
    return try dir(alloc, opts, .{
        .env = "XDG_STATE_HOME",
        .windows_env = "LOCALAPPDATA",
        .default_subdir = ".local/state",
        .windows_home_subdir = "AppData\\Local",
    });
}

const InternalOptions = struct {
    env: []const u8,
    windows_env: []const u8,
    windows_env_fallback: ?[]const u8 = null,
    default_subdir: []const u8,
    windows_home_subdir: ?[]const u8 = null,
};

/// Unified helper to get XDG directories that follow a common pattern.
fn dir(
    alloc: Allocator,
    opts: Options,
    internal_opts: InternalOptions,
) ![]u8 {
    // If we have a cached home dir, use that.
    if (opts.home) |home| {
        const home_subdir = if (builtin.os.tag == .windows)
            internal_opts.windows_home_subdir orelse internal_opts.default_subdir
        else
            internal_opts.default_subdir;
        return try std.fs.path.join(alloc, &[_][]const u8{
            home,
            home_subdir,
            opts.subdir orelse "",
        });
    }

    // First check the env var. On Windows we have to allocate so this tracks
    // both whether we have the env var and whether we own it.
    // On Windows we treat XDG env as primary, then our Windows env fallback(s).
    const env_ = try env_os.getenvNotEmpty(alloc, internal_opts.env) orelse switch (builtin.os.tag) {
        else => null,
        .windows => (try env_os.getenvNotEmpty(alloc, internal_opts.windows_env)) orelse
            if (internal_opts.windows_env_fallback) |fallback|
            try env_os.getenvNotEmpty(alloc, fallback)
            else
                null,
    };
    defer if (env_) |env| env.deinit(alloc);

    if (env_) |env| {
        // If we have a subdir, then we use the env as-is to avoid a copy.
        if (opts.subdir) |subdir| {
            return try std.fs.path.join(alloc, &[_][]const u8{
                env.value,
                subdir,
            });
        }

        return try alloc.dupe(u8, env.value);
    }

    // Get our home dir
    var buf: [1024]u8 = undefined;
    if (try homedir.home(&buf)) |home| {
        const home_subdir = if (builtin.os.tag == .windows)
            internal_opts.windows_home_subdir orelse internal_opts.default_subdir
        else
            internal_opts.default_subdir;
        return try std.fs.path.join(alloc, &[_][]const u8{
            home,
            home_subdir,
            opts.subdir orelse "",
        });
    }

    return error.NoHomeDir;
}

/// Parses the xdg-terminal-exec specification. This expects argv[0] to
/// be "xdg-terminal-exec".
pub fn parseTerminalExec(argv: []const [*:0]const u8) ?[]const [*:0]const u8 {
    if (!std.mem.eql(
        u8,
        std.fs.path.basename(std.mem.sliceTo(argv[0], 0)),
        "xdg-terminal-exec",
    )) return null;

    // We expect at least one argument
    if (argv.len < 2) return &.{};

    // If the first argument is "-e" we skip it.
    const start: usize = if (std.mem.eql(u8, std.mem.sliceTo(argv[1], 0), "-e")) 2 else 1;
    return argv[start..];
}

test {
    const testing = std.testing;
    const alloc = testing.allocator;

    {
        const value = try config(alloc, .{});
        defer alloc.free(value);
        try testing.expect(value.len > 0);
    }
}

test "cache directory paths" {
    const testing = std.testing;
    const alloc = testing.allocator;
    const mock_home = "/Users/test";

    // Test when XDG_CACHE_HOME is not set
    {
        // Test base path
        {
            const cache_path = try cache(alloc, .{ .home = mock_home });
            defer alloc.free(cache_path);
            try testing.expectEqualStrings("/Users/test/.cache", cache_path);
        }

        // Test with subdir
        {
            const cache_path = try cache(alloc, .{
                .home = mock_home,
                .subdir = "ghostty",
            });
            defer alloc.free(cache_path);
            try testing.expectEqualStrings("/Users/test/.cache/ghostty", cache_path);
        }
    }
}

test "fallback when xdg env empty" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const alloc = std.testing.allocator;

    const saved_home = home: {
        const home = std.posix.getenv("HOME") orelse break :home null;
        break :home try alloc.dupeZ(u8, home);
    };
    defer env: {
        const home = saved_home orelse {
            _ = env_os.unsetenv("HOME");
            break :env;
        };
        _ = env_os.setenv("HOME", home);
        std.testing.allocator.free(home);
    }
    const temp_home = "/tmp/ghostty-test-home";
    _ = env_os.setenv("HOME", temp_home);

    const DirCase = struct {
        name: [:0]const u8,
        func: fn (Allocator, Options) anyerror![]u8,
        default_subdir: []const u8,
    };

    const cases = [_]DirCase{
        .{ .name = "XDG_CONFIG_HOME", .func = config, .default_subdir = ".config" },
        .{ .name = "XDG_CACHE_HOME", .func = cache, .default_subdir = ".cache" },
        .{ .name = "XDG_STATE_HOME", .func = state, .default_subdir = ".local/state" },
    };

    inline for (cases) |case| {
        // Save and restore each environment variable
        const saved_env = blk: {
            const value = std.posix.getenv(case.name) orelse break :blk null;
            break :blk try alloc.dupeZ(u8, value);
        };
        defer env: {
            const value = saved_env orelse {
                _ = env_os.unsetenv(case.name);
                break :env;
            };
            _ = env_os.setenv(case.name, value);
            alloc.free(value);
        }

        const expected = try std.fs.path.join(alloc, &[_][]const u8{
            temp_home,
            case.default_subdir,
        });
        defer alloc.free(expected);

        // Test with empty string - should fallback to home
        _ = env_os.setenv(case.name, "");
        const actual = try case.func(alloc, .{});
        defer alloc.free(actual);

        try std.testing.expectEqualStrings(expected, actual);
    }
}

test "fallback when xdg env empty and subdir" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const env = @import("env.zig");
    const alloc = std.testing.allocator;

    const saved_home = home: {
        const home = std.posix.getenv("HOME") orelse break :home null;
        break :home try alloc.dupeZ(u8, home);
    };
    defer env: {
        const home = saved_home orelse {
            _ = env.unsetenv("HOME");
            break :env;
        };
        _ = env.setenv("HOME", home);
        std.testing.allocator.free(home);
    }

    const temp_home = "/tmp/ghostty-test-home";
    _ = env.setenv("HOME", temp_home);

    const DirCase = struct {
        name: [:0]const u8,
        func: fn (Allocator, Options) anyerror![]u8,
        default_subdir: []const u8,
    };

    const cases = [_]DirCase{
        .{ .name = "XDG_CONFIG_HOME", .func = config, .default_subdir = ".config" },
        .{ .name = "XDG_CACHE_HOME", .func = cache, .default_subdir = ".cache" },
        .{ .name = "XDG_STATE_HOME", .func = state, .default_subdir = ".local/state" },
    };

    inline for (cases) |case| {
        // Save and restore each environment variable
        const saved_env = blk: {
            const value = std.posix.getenv(case.name) orelse break :blk null;
            break :blk try alloc.dupeZ(u8, value);
        };
        defer env: {
            const value = saved_env orelse {
                _ = env.unsetenv(case.name);
                break :env;
            };
            _ = env.setenv(case.name, value);
            alloc.free(value);
        }

        const expected = try std.fs.path.join(alloc, &[_][]const u8{
            temp_home,
            case.default_subdir,
            "ghostty",
        });
        defer alloc.free(expected);

        // Test with empty string - should fallback to home
        _ = env.setenv(case.name, "");
        const actual = try case.func(alloc, .{ .subdir = "ghostty" });
        defer alloc.free(actual);

        try std.testing.expectEqualStrings(expected, actual);
    }
}

test "windows config uses localappdata then appdata" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const alloc = std.testing.allocator;

    const saved_xdg = blk: {
        const value = try env_os.getenv(alloc, "XDG_CONFIG_HOME") orelse break :blk null;
        defer value.deinit(alloc);
        break :blk try alloc.dupeZ(u8, value.value);
    };
    const saved_local = blk: {
        const value = try env_os.getenv(alloc, "LOCALAPPDATA") orelse break :blk null;
        defer value.deinit(alloc);
        break :blk try alloc.dupeZ(u8, value.value);
    };
    const saved_app = blk: {
        const value = try env_os.getenv(alloc, "APPDATA") orelse break :blk null;
        defer value.deinit(alloc);
        break :blk try alloc.dupeZ(u8, value.value);
    };
    defer {
        if (saved_xdg) |value| {
            _ = env_os.setenv("XDG_CONFIG_HOME", value);
            alloc.free(value);
        } else {
            _ = env_os.unsetenv("XDG_CONFIG_HOME");
        }
        if (saved_local) |value| {
            _ = env_os.setenv("LOCALAPPDATA", value);
            alloc.free(value);
        } else {
            _ = env_os.unsetenv("LOCALAPPDATA");
        }
        if (saved_app) |value| {
            _ = env_os.setenv("APPDATA", value);
            alloc.free(value);
        } else {
            _ = env_os.unsetenv("APPDATA");
        }
    }

    _ = env_os.setenv("XDG_CONFIG_HOME", "");
    _ = env_os.setenv("LOCALAPPDATA", "C:\\Users\\test\\AppData\\Local");
    _ = env_os.setenv("APPDATA", "C:\\Users\\test\\AppData\\Roaming");

    {
        const path = try config(alloc, .{});
        defer alloc.free(path);
        try std.testing.expectEqualStrings(
            "C:\\Users\\test\\AppData\\Local",
            path,
        );
    }

    _ = env_os.setenv("LOCALAPPDATA", "");

    {
        const path = try config(alloc, .{});
        defer alloc.free(path);
        try std.testing.expectEqualStrings(
            "C:\\Users\\test\\AppData\\Roaming",
            path,
        );
    }
}

test parseTerminalExec {
    const testing = std.testing;

    {
        const actual = parseTerminalExec(&.{ "a", "b", "c" });
        try testing.expect(actual == null);
    }
    {
        const actual = parseTerminalExec(&.{"xdg-terminal-exec"}).?;
        try testing.expectEqualSlices([*:0]const u8, actual, &.{});
    }
    {
        const actual = parseTerminalExec(&.{ "xdg-terminal-exec", "a", "b", "c" }).?;
        try testing.expectEqualSlices([*:0]const u8, actual, &.{ "a", "b", "c" });
    }
    {
        const actual = parseTerminalExec(&.{ "xdg-terminal-exec", "-e", "a", "b", "c" }).?;
        try testing.expectEqualSlices([*:0]const u8, actual, &.{ "a", "b", "c" });
    }
    {
        const actual = parseTerminalExec(&.{ "xdg-terminal-exec", "a", "-e", "b", "c" }).?;
        try testing.expectEqualSlices([*:0]const u8, actual, &.{ "a", "-e", "b", "c" });
    }
}
