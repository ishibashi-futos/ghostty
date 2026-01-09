const Surface = @This();

const std = @import("std");
const win = std.os.windows;
const windows = @import("../../os/windows.zig");
const apprt = @import("../../apprt.zig");
const configpkg = @import("../../config.zig");
const Config = configpkg.Config;
const CoreSurface = @import("../../Surface.zig");
const App = @import("App.zig");
const angle = @import("angle.zig");

const CF_UNICODETEXT: win.UINT = 13;
const GMEM_MOVEABLE: win.UINT = 0x0002;

const POINT = extern struct {
    x: win.LONG,
    y: win.LONG,
};

const RECT = extern struct {
    left: win.LONG,
    top: win.LONG,
    right: win.LONG,
    bottom: win.LONG,
};

const kernel32 = struct {
    pub extern "kernel32" fn GlobalAlloc(
        uFlags: win.UINT,
        dwBytes: win.SIZE_T,
    ) callconv(.winapi) ?win.HANDLE;
    pub extern "kernel32" fn GlobalLock(
        hMem: win.HANDLE,
    ) callconv(.winapi) ?*anyopaque;
    pub extern "kernel32" fn GlobalUnlock(
        hMem: win.HANDLE,
    ) callconv(.winapi) win.BOOL;
    pub extern "kernel32" fn GlobalSize(
        hMem: win.HANDLE,
    ) callconv(.winapi) win.SIZE_T;
    pub extern "kernel32" fn GlobalFree(
        hMem: win.HANDLE,
    ) callconv(.winapi) ?win.HANDLE;
};

const user32 = struct {
    pub extern "user32" fn GetDpiForWindow(
        hWnd: win.HWND,
    ) callconv(.winapi) win.UINT;
    pub extern "user32" fn OpenClipboard(
        hWndNewOwner: ?win.HWND,
    ) callconv(.winapi) win.BOOL;
    pub extern "user32" fn CloseClipboard() callconv(.winapi) win.BOOL;
    pub extern "user32" fn EmptyClipboard() callconv(.winapi) win.BOOL;
    pub extern "user32" fn GetClipboardData(
        uFormat: win.UINT,
    ) callconv(.winapi) ?win.HANDLE;
    pub extern "user32" fn SetClipboardData(
        uFormat: win.UINT,
        hMem: ?win.HANDLE,
    ) callconv(.winapi) ?win.HANDLE;
    pub extern "user32" fn IsClipboardFormatAvailable(
        format: win.UINT,
    ) callconv(.winapi) win.BOOL;
    pub extern "user32" fn GetClientRect(
        hWnd: win.HWND,
        lpRect: *RECT,
    ) callconv(.winapi) win.BOOL;
    pub extern "user32" fn GetCursorPos(
        lpPoint: *POINT,
    ) callconv(.winapi) win.BOOL;
    pub extern "user32" fn ScreenToClient(
        hWnd: win.HWND,
        lpPoint: *POINT,
    ) callconv(.winapi) win.BOOL;
};

rt_app: *App,
core_surface: CoreSurface = undefined,
initialized: bool = false,
angle_ctx: ?angle.Context = null,

pub fn init(self: *Surface, app: *App, config: *const Config) !void {
    self.* = .{
        .rt_app = app,
        .core_surface = undefined,
        .initialized = false,
        .angle_ctx = null,
    };

    try app.core_app.addSurface(self);
    errdefer app.core_app.deleteSurface(self);

    try self.core_surface.init(
        app.core_app.alloc,
        config,
        app.core_app,
        app,
        self,
    );
    self.initialized = true;
}

pub fn core(self: *Surface) *CoreSurface {
    return &self.core_surface;
}

pub fn deinit(self: *Surface) void {
    if (self.initialized) {
        self.core_surface.deinit();
        self.initialized = false;
    }
    if (self.angle_ctx) |*ctx| {
        ctx.deinit();
        self.angle_ctx = null;
    }
    self.rt_app.core_app.deleteSurface(self);
}

pub fn rtApp(self: *Surface) *App {
    return self.rt_app;
}

pub fn ensureAngleContext(self: *Surface) !*angle.Context {
    if (self.angle_ctx) |*ctx| return ctx;
    const hwnd = self.rt_app.hwnd orelse return error.AngleMissingWindow;
    self.angle_ctx = try angle.Context.init(hwnd);
    return &self.angle_ctx.?;
}

pub fn angleSwapBuffers(self: *Surface) void {
    if (self.angle_ctx) |*ctx| {
        ctx.swapBuffers();
    }
}

pub fn close(self: *Surface, process_active: bool) void {
    _ = self;
    _ = process_active;
}

pub fn cgroup(self: *Surface) ?[]const u8 {
    _ = self;
    return null;
}

pub fn getTitle(self: *Surface) ?[:0]const u8 {
    _ = self;
    return null;
}

pub fn getContentScale(self: *const Surface) !apprt.ContentScale {
    const hwnd = self.rt_app.hwnd orelse return .{ .x = 1, .y = 1 };
    const dpi = user32.GetDpiForWindow(hwnd);
    if (dpi == 0) return .{ .x = 1, .y = 1 };
    const scale = @as(f32, @floatFromInt(dpi)) / 96.0;
    return .{ .x = scale, .y = scale };
}

pub fn getSize(self: *const Surface) !apprt.SurfaceSize {
    const hwnd = self.rt_app.hwnd orelse return .{ .width = 800, .height = 600 };
    var rect: RECT = undefined;
    if (user32.GetClientRect(hwnd, &rect) == 0) {
        return .{ .width = 800, .height = 600 };
    }

    const width = @as(u32, @intCast(@max(0, rect.right - rect.left)));
    const height = @as(u32, @intCast(@max(0, rect.bottom - rect.top)));
    return .{ .width = width, .height = height };
}

pub fn getCursorPos(self: *const Surface) !apprt.CursorPos {
    const hwnd = self.rt_app.hwnd orelse return .{ .x = 0, .y = 0 };
    var point: POINT = undefined;
    if (user32.GetCursorPos(&point) == 0) {
        return .{ .x = 0, .y = 0 };
    }
    if (user32.ScreenToClient(hwnd, &point) == 0) {
        return .{ .x = 0, .y = 0 };
    }

    return .{
        .x = @floatFromInt(point.x),
        .y = @floatFromInt(point.y),
    };
}

pub fn supportsClipboard(
    self: *const Surface,
    clipboard_type: apprt.Clipboard,
) bool {
    _ = self;
    return clipboard_type == .standard;
}

pub fn clipboardRequest(
    self: *Surface,
    clipboard_type: apprt.Clipboard,
    state: apprt.ClipboardRequest,
) !bool {
    if (clipboard_type != .standard) return false;

    const text = try self.readClipboardText();
    if (text == null) return false;
    defer self.rt_app.core_app.alloc.free(text.?);

    try self.core_surface.completeClipboardRequest(
        state,
        text.?,
        false,
    );
    return true;
}

pub fn setClipboard(
    self: *Surface,
    clipboard_type: apprt.Clipboard,
    contents: []const apprt.ClipboardContent,
    confirm: bool,
) !void {
    _ = confirm;

    if (clipboard_type != .standard) return;
    const text = findClipboardText(contents) orelse return;
    try self.writeClipboardText(text);
}

pub fn defaultTermioEnv(self: *Surface) !std.process.EnvMap {
    return try std.process.getEnvMap(self.rt_app.core_app.alloc);
}

pub fn redrawInspector(self: *Surface) void {
    _ = self;
}

fn findClipboardText(contents: []const apprt.ClipboardContent) ?[:0]const u8 {
    for (contents) |content| {
        if (std.mem.eql(u8, content.mime, "text/plain")) {
            return content.data;
        }
    }
    return null;
}

fn readClipboardText(self: *Surface) !?[:0]u8 {
    if (user32.IsClipboardFormatAvailable(CF_UNICODETEXT) == 0) {
        return null;
    }

    const hwnd = self.rt_app.hwnd;
    if (user32.OpenClipboard(hwnd) == 0) {
        return windows.unexpectedError(win.kernel32.GetLastError());
    }
    defer _ = user32.CloseClipboard();

    const handle = user32.GetClipboardData(CF_UNICODETEXT) orelse return null;
    const locked = kernel32.GlobalLock(handle) orelse
        return windows.unexpectedError(win.kernel32.GetLastError());
    defer _ = kernel32.GlobalUnlock(handle);

    const size_bytes = kernel32.GlobalSize(handle);
    if (size_bytes == 0) return null;

    const wchar_count: usize = @intCast(size_bytes / @sizeOf(u16));
    const buffer = @as([*]const u16, @ptrCast(@alignCast(locked)))[0..wchar_count];
    const text16 = std.mem.sliceTo(buffer, 0);
    const alloc = self.rt_app.core_app.alloc;
    return try std.unicode.utf16LeToUtf8AllocZ(alloc, text16);
}

fn writeClipboardText(self: *Surface, text: []const u8) !void {
    const alloc = self.rt_app.core_app.alloc;
    const utf16 = try std.unicode.utf8ToUtf16LeAllocZ(alloc, text);
    defer alloc.free(utf16);

    const hwnd = self.rt_app.hwnd;
    if (user32.OpenClipboard(hwnd) == 0) {
        return windows.unexpectedError(win.kernel32.GetLastError());
    }
    defer _ = user32.CloseClipboard();

    if (user32.EmptyClipboard() == 0) {
        return windows.unexpectedError(win.kernel32.GetLastError());
    }

    const utf16_len = utf16.len + 1;
    const size_bytes: win.SIZE_T = utf16_len * @sizeOf(u16);
    const handle = kernel32.GlobalAlloc(GMEM_MOVEABLE, size_bytes) orelse
        return windows.unexpectedError(win.kernel32.GetLastError());
    errdefer _ = kernel32.GlobalFree(handle);

    const locked = kernel32.GlobalLock(handle) orelse
        return windows.unexpectedError(win.kernel32.GetLastError());
    defer _ = kernel32.GlobalUnlock(handle);

    const dest = @as([*]u16, @ptrCast(@alignCast(locked)))[0..utf16_len];
    std.mem.copyForwards(u16, dest, utf16[0..utf16_len]);

    if (user32.SetClipboardData(CF_UNICODETEXT, handle) == null) {
        return windows.unexpectedError(win.kernel32.GetLastError());
    }
}
