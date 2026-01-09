const std = @import("std");
const builtin = @import("builtin");
const env_os = @import("env.zig");
const path_os = @import("path.zig");

/// Returns true when running under WSL (Linux) or when WSL is installed (Windows).
pub fn isWsl() bool {
    return switch (builtin.os.tag) {
        .linux => isWslLinux(),
        .windows => hasWslExe(),
        else => false,
    };
}

fn isWslLinux() bool {
    if (std.posix.getenv("WSL_INTEROP") != null) return true;
    if (std.posix.getenv("WSL_DISTRO_NAME") != null) return true;

    return fileContainsMicrosoft("/proc/sys/kernel/osrelease") or
        fileContainsMicrosoft("/proc/version");
}

fn fileContainsMicrosoft(path: []const u8) bool {
    var buf: [256]u8 = undefined;
    const file = std.fs.openFileAbsolute(path, .{}) catch return false;
    defer file.close();

    const n = file.read(&buf) catch return false;
    for (buf[0..n]) |*b| {
        b.* = std.ascii.toLower(b.*);
    }

    return std.mem.indexOf(u8, buf[0..n], "microsoft") != null;
}

fn hasWslExe() bool {
    const alloc = std.heap.page_allocator;

    if (env_os.getenvNotEmpty(alloc, "SystemRoot") catch null) |value| {
        defer value.deinit(alloc);
        const path = std.fs.path.join(alloc, &[_][]const u8{
            value.value,
            "System32",
            "wsl.exe",
        }) catch return false;
        defer alloc.free(path);
        if (std.fs.openFileAbsolute(path, .{})) |file| {
            file.close();
            return true;
        } else |_| {}
    }

    const found = path_os.expand(alloc, "wsl.exe") catch null;
    if (found) |value| {
        alloc.free(value);
        return true;
    }

    return false;
}

