const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const ipc = @import("ipc.zig");
const windows = @import("../os/windows.zig");

const log = std.log.scoped(.ipc_windows);

const pipe_prefix = "\\\\.\\pipe\\ghostty-";
const max_args = 64;
const wait_timeout_ms: windows.DWORD = 500;

const default_class = switch (builtin.mode) {
    .Debug, .ReleaseSafe => "com.mitchellh.ghostty-debug",
    .ReleaseFast, .ReleaseSmall => "com.mitchellh.ghostty",
};

pub const Request = struct {
    action: ipc.Action.Key,
    new_window: ?ipc.Action.NewWindow = null,

    pub fn deinit(self: *Request, alloc: Allocator) void {
        if (self.new_window) |*value| {
            if (value.arguments) |arguments| {
                for (arguments) |arg| {
                    alloc.free(arg);
                }
                alloc.free(arguments);
            }
        }
        self.* = undefined;
    }
};

pub const Server = struct {
    handle: windows.HANDLE,
    name: [:0]const u16,

    pub fn init(alloc: Allocator, class: ?[:0]const u8) !Server {
        if (builtin.os.tag != .windows) return error.UnsupportedPlatform;

        const name = try pipeName(alloc, class orelse default_class);
        errdefer alloc.free(name);

        const handle = windows.exp.kernel32.CreateNamedPipeW(
            name.ptr,
            windows.exp.PIPE_ACCESS_INBOUND | windows.exp.FILE_FLAG_FIRST_PIPE_INSTANCE,
            windows.exp.PIPE_TYPE_BYTE | windows.exp.PIPE_READMODE_BYTE | windows.exp.PIPE_WAIT,
            1,
            64 * 1024,
            64 * 1024,
            0,
            null,
        );
        if (handle == windows.INVALID_HANDLE_VALUE) {
            return windows.unexpectedError(windows.kernel32.GetLastError());
        }

        return .{ .handle = handle, .name = name };
    }

    pub fn deinit(self: *Server, alloc: Allocator) void {
        _ = windows.exp.kernel32.DisconnectNamedPipe(self.handle);
        windows.CloseHandle(self.handle);
        alloc.free(self.name);
        self.* = undefined;
    }

    pub fn accept(self: *Server, alloc: Allocator) !Request {
        if (builtin.os.tag != .windows) return error.UnsupportedPlatform;

        if (windows.exp.kernel32.ConnectNamedPipe(self.handle, null) == 0) {
            const err = windows.kernel32.GetLastError();
            if (err != windows.exp.ERROR_PIPE_CONNECTED) {
                return windows.unexpectedError(err);
            }
        }

        var file = std.fs.File{ .handle = self.handle };
        var len_buf: [4]u8 = undefined;
        try file.reader().readNoEof(&len_buf);
        const payload_len = std.mem.readInt(u32, len_buf[0..], .little);
        if (payload_len == 0 or payload_len > 256 * 1024) return error.InvalidMessage;

        const payload = try alloc.alloc(u8, payload_len);
        defer alloc.free(payload);
        try file.reader().readNoEof(payload);

        _ = windows.exp.kernel32.DisconnectNamedPipe(self.handle);
        return try decodeRequest(alloc, payload);
    }
};

pub fn sendNewWindow(
    alloc: Allocator,
    target: ipc.Target,
    value: ipc.Action.NewWindow,
) (Allocator.Error || std.Io.Writer.Error || ipc.Errors)!bool {
    if (builtin.os.tag != .windows) return false;

    const handle = try openPipe(alloc, target) orelse return false;
    defer windows.CloseHandle(handle);

    var file = std.fs.File{ .handle = handle };
    const payload = try encodeNewWindow(alloc, value);
    defer alloc.free(payload);

    var writer = file.writer();
    try writer.writeIntLittle(u32, @intCast(payload.len));
    try writer.writeAll(payload);
    return true;
}

fn openPipe(alloc: Allocator, target: ipc.Target) !?windows.HANDLE {
    const name = try pipeNameForTarget(alloc, target);
    defer alloc.free(name);

    var handle = windows.exp.kernel32.CreateFileW(
        name.ptr,
        windows.GENERIC_READ | windows.GENERIC_WRITE,
        0,
        null,
        windows.OPEN_EXISTING,
        windows.FILE_ATTRIBUTE_NORMAL,
        null,
    );

    if (handle == windows.INVALID_HANDLE_VALUE) {
        const err = windows.kernel32.GetLastError();
        switch (err) {
            windows.exp.ERROR_FILE_NOT_FOUND => return null,
            windows.exp.ERROR_PIPE_BUSY => {
                if (windows.exp.kernel32.WaitNamedPipeW(name.ptr, wait_timeout_ms) == 0)
                    return null;
                handle = windows.exp.kernel32.CreateFileW(
                    name.ptr,
                    windows.GENERIC_READ | windows.GENERIC_WRITE,
                    0,
                    null,
                    windows.OPEN_EXISTING,
                    windows.FILE_ATTRIBUTE_NORMAL,
                    null,
                );
                if (handle == windows.INVALID_HANDLE_VALUE) {
                    const retry_err = windows.kernel32.GetLastError();
                    if (retry_err == windows.exp.ERROR_FILE_NOT_FOUND) return null;
                    log.err("named pipe connect failed err={}", .{retry_err});
                    return error.IPCFailed;
                }
            },
            else => {
                log.err("named pipe connect failed err={}", .{err});
                return error.IPCFailed;
            },
        }
    }

    return handle;
}

fn pipeNameForTarget(alloc: Allocator, target: ipc.Target) ![:0]const u16 {
    return switch (target) {
        .class => |class| pipeName(alloc, class),
        .detect => pipeName(alloc, default_class),
    };
}

fn pipeName(alloc: Allocator, class: []const u8) ![:0]const u16 {
    const safe_class = try sanitizePipeComponent(alloc, class);
    defer alloc.free(safe_class);

    const name = try std.fmt.allocPrint(alloc, "{s}{s}", .{ pipe_prefix, safe_class });
    defer alloc.free(name);

    return std.unicode.utf8ToUtf16LeAllocZ(alloc, name);
}

fn sanitizePipeComponent(alloc: Allocator, input: []const u8) ![]u8 {
    var out = std.ArrayList(u8).init(alloc);
    errdefer out.deinit();

    for (input) |c| {
        switch (c) {
            '\\', '/', ':', '*', '?', '"', '<', '>', '|' => try out.append('_'),
            else => try out.append(c),
        }
    }

    return try out.toOwnedSlice();
}

fn encodeNewWindow(alloc: Allocator, value: ipc.Action.NewWindow) ![]u8 {
    var out = std.ArrayList(u8).init(alloc);
    errdefer out.deinit();
    var writer = out.writer();

    try writer.writeIntLittle(u32, @intFromEnum(ipc.Action.Key.new_window));

    const argc: u32 = if (value.arguments) |arguments|
        @intCast(arguments.len)
    else
        0;
    try writer.writeIntLittle(u32, argc);

    if (value.arguments) |arguments| {
        for (arguments) |arg| {
            try writer.writeIntLittle(u32, @intCast(arg.len));
            try writer.writeAll(arg);
        }
    }

    return try out.toOwnedSlice();
}

fn decodeRequest(alloc: Allocator, payload: []const u8) !Request {
    var fbs = std.io.fixedBufferStream(payload);
    const reader = fbs.reader();

    const action_raw = try reader.readIntLittle(u32);
    const action = std.meta.intToEnum(ipc.Action.Key, action_raw) catch return error.InvalidMessage;

    var request: Request = .{ .action = action };
    switch (action) {
        .new_window => {
            const argc = try reader.readIntLittle(u32);
            if (argc > max_args) return error.InvalidMessage;

            if (argc == 0) {
                request.new_window = .{ .arguments = null };
                return request;
            }

            var args = try alloc.alloc([:0]const u8, argc);
            errdefer {
                for (args) |arg| alloc.free(arg);
                alloc.free(args);
            }

            var i: usize = 0;
            while (i < argc) : (i += 1) {
                const len = try reader.readIntLittle(u32);
                if (len == 0) return error.InvalidMessage;

                var arg = try alloc.alloc(u8, len + 1);
                errdefer alloc.free(arg);
                try reader.readNoEof(arg[0..len]);
                arg[len] = 0;
                args[i] = arg[0..len :0];
            }

            request.new_window = .{ .arguments = args };
        },
    }

    return request;
}
