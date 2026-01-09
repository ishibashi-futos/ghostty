const Surface = @This();

const std = @import("std");
const win = std.os.windows;
const apprt = @import("../../apprt.zig");
const CoreSurface = @import("../../Surface.zig");
const App = @import("App.zig");

const user32 = struct {
    pub extern "user32" fn GetDpiForWindow(
        hWnd: win.HWND,
    ) callconv(.winapi) win.UINT;
};

rt_app: *App,
core_surface: ?*CoreSurface = null,

pub fn core(self: *Surface) *CoreSurface {
    return self.core_surface orelse @panic("win32 surface missing core surface");
}

pub fn deinit(self: *Surface) void {
    _ = self;
}

pub fn rtApp(self: *Surface) *App {
    return self.rt_app;
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
    _ = self;
    return .{ .width = 800, .height = 600 };
}

pub fn getCursorPos(self: *const Surface) !apprt.CursorPos {
    _ = self;
    return .{ .x = 0, .y = 0 };
}

pub fn supportsClipboard(
    self: *const Surface,
    clipboard_type: apprt.Clipboard,
) bool {
    _ = self;
    _ = clipboard_type;
    return false;
}

pub fn clipboardRequest(
    self: *Surface,
    clipboard_type: apprt.Clipboard,
    state: apprt.ClipboardRequest,
) !bool {
    _ = self;
    _ = clipboard_type;
    _ = state;
    return false;
}

pub fn setClipboard(
    self: *Surface,
    clipboard_type: apprt.Clipboard,
    contents: []const apprt.ClipboardContent,
    confirm: bool,
) !void {
    _ = self;
    _ = clipboard_type;
    _ = contents;
    _ = confirm;
}

pub fn defaultTermioEnv(self: *Surface) !std.process.EnvMap {
    return try std.process.getEnvMap(self.rt_app.core_app.alloc);
}

pub fn redrawInspector(self: *Surface) void {
    _ = self;
}
