const std = @import("std");
const builtin = @import("builtin");
const windows = @import("windows.zig");
const posix = std.posix;

/// pipe() that works on Windows and POSIX. For POSIX systems, this sets
/// CLOEXEC on the file descriptors.
pub fn pipe() ![2]posix.fd_t {
    switch (builtin.os.tag) {
        else => return try posix.pipe2(.{ .CLOEXEC = true }),
        .windows => {
            var read: windows.HANDLE = undefined;
            var write: windows.HANDLE = undefined;
            if (windows.exp.kernel32.CreatePipe(&read, &write, null, 0) == 0) {
                return windows.unexpectedError(windows.kernel32.GetLastError());
            }

            _ = windows.SetHandleInformation(read, windows.HANDLE_FLAG_INHERIT, 0);
            _ = windows.SetHandleInformation(write, windows.HANDLE_FLAG_INHERIT, 0);

            return .{ read, write };
        },
    }
}

test "pipe basic" {
    const testing = std.testing;
    const fds = try pipe();

    var read_file = std.fs.File{ .handle = fds[0] };
    var write_file = std.fs.File{ .handle = fds[1] };
    defer read_file.close();
    defer write_file.close();

    try write_file.writeAll("hello");

    var buf: [5]u8 = undefined;
    try read_file.reader().readNoEof(&buf);
    try testing.expectEqualStrings("hello", &buf);
}
