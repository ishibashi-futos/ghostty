const App = @This();

const std = @import("std");
const builtin = @import("builtin");
const win = std.os.windows;
const windows = @import("../../os/windows.zig");
const apprt = @import("../../apprt.zig");
const configpkg = @import("../../config.zig");
const Config = configpkg.Config;
const CoreApp = @import("../../App.zig");
const ipc_windows = @import("../ipc_windows.zig");
const Surface = @import("Surface.zig");

const class_name = std.unicode.utf8ToUtf16LeStringLiteral("GhosttyWin32");
const window_title = std.unicode.utf8ToUtf16LeStringLiteral("Ghostty (Win32)");

const WM_DESTROY: win.UINT = 0x0002;
const WM_CLOSE: win.UINT = 0x0010;
const WM_APP: win.UINT = 0x8000;
const CS_HREDRAW: win.UINT = 0x0002;
const CS_VREDRAW: win.UINT = 0x0001;
const WS_OVERLAPPEDWINDOW: win.DWORD = 0x00CF0000;
const WS_VISIBLE: win.DWORD = 0x10000000;
const CW_USEDEFAULT: win.INT = @bitCast(@as(u32, 0x80000000));
const SW_SHOWDEFAULT: win.INT = 10;
const ERROR_CLASS_ALREADY_EXISTS: win.Win32Error = .CLASS_ALREADY_EXISTS;
const IDC_ARROW: win.LPCWSTR = @ptrFromInt(@as(usize, 32512));

const POINT = extern struct {
    x: win.LONG,
    y: win.LONG,
};

const MSG = extern struct {
    hwnd: ?win.HWND,
    message: win.UINT,
    wParam: win.WPARAM,
    lParam: win.LPARAM,
    time: win.DWORD,
    pt: POINT,
};

const WNDPROC = *const fn (
    win.HWND,
    win.UINT,
    win.WPARAM,
    win.LPARAM,
) callconv(.winapi) win.LRESULT;

const WNDCLASSEXW = extern struct {
    cbSize: win.UINT,
    style: win.UINT,
    lpfnWndProc: WNDPROC,
    cbClsExtra: win.INT,
    cbWndExtra: win.INT,
    hInstance: ?win.HINSTANCE,
    hIcon: ?win.HICON,
    hCursor: ?win.HCURSOR,
    hbrBackground: ?win.HBRUSH,
    lpszMenuName: ?win.LPCWSTR,
    lpszClassName: win.LPCWSTR,
    hIconSm: ?win.HICON,
};

const kernel32 = struct {
    pub extern "kernel32" fn GetModuleHandleW(
        lpModuleName: ?win.LPCWSTR,
    ) callconv(.winapi) ?win.HMODULE;
};

const user32 = struct {
    pub extern "user32" fn RegisterClassExW(
        lpWndClass: *const WNDCLASSEXW,
    ) callconv(.winapi) win.ATOM;
    pub extern "user32" fn CreateWindowExW(
        dwExStyle: win.DWORD,
        lpClassName: win.LPCWSTR,
        lpWindowName: win.LPCWSTR,
        dwStyle: win.DWORD,
        X: win.INT,
        Y: win.INT,
        nWidth: win.INT,
        nHeight: win.INT,
        hWndParent: ?win.HWND,
        hMenu: ?win.HMENU,
        hInstance: ?win.HINSTANCE,
        lpParam: ?*anyopaque,
    ) callconv(.winapi) ?win.HWND;
    pub extern "user32" fn DefWindowProcW(
        hWnd: win.HWND,
        Msg: win.UINT,
        wParam: win.WPARAM,
        lParam: win.LPARAM,
    ) callconv(.winapi) win.LRESULT;
    pub extern "user32" fn ShowWindow(
        hWnd: win.HWND,
        nCmdShow: win.INT,
    ) callconv(.winapi) win.BOOL;
    pub extern "user32" fn UpdateWindow(
        hWnd: win.HWND,
    ) callconv(.winapi) win.BOOL;
    pub extern "user32" fn GetMessageW(
        lpMsg: *MSG,
        hWnd: ?win.HWND,
        wMsgFilterMin: win.UINT,
        wMsgFilterMax: win.UINT,
    ) callconv(.winapi) win.BOOL;
    pub extern "user32" fn TranslateMessage(
        lpMsg: *const MSG,
    ) callconv(.winapi) win.BOOL;
    pub extern "user32" fn DispatchMessageW(
        lpMsg: *const MSG,
    ) callconv(.winapi) win.LRESULT;
    pub extern "user32" fn PostQuitMessage(
        nExitCode: win.INT,
    ) callconv(.winapi) void;
    pub extern "user32" fn LoadCursorW(
        hInstance: ?win.HINSTANCE,
        lpCursorName: win.LPCWSTR,
    ) callconv(.winapi) ?win.HCURSOR;
    pub extern "user32" fn PostMessageW(
        hWnd: ?win.HWND,
        Msg: win.UINT,
        wParam: win.WPARAM,
        lParam: win.LPARAM,
    ) callconv(.winapi) win.BOOL;
    pub extern "user32" fn DestroyWindow(
        hWnd: win.HWND,
    ) callconv(.winapi) win.BOOL;
};

core_app: *CoreApp,
config: Config,
hinstance: ?win.HINSTANCE = null,
hwnd: ?win.HWND = null,

pub fn init(
    self: *App,
    core_app: *CoreApp,
    opts: struct {},
) !void {
    _ = opts;
    if (comptime builtin.os.tag != .windows) return error.UnsupportedPlatform;

    var config = try Config.default(core_app.alloc);
    errdefer config.deinit();

    const hmodule = kernel32.GetModuleHandleW(null) orelse
        return windows.unexpectedError(win.kernel32.GetLastError());

    const hinstance: win.HINSTANCE = @ptrCast(hmodule);
    try registerWindowClass(hinstance);
    const hwnd = try createWindow(hinstance);

    self.* = .{
        .core_app = core_app,
        .config = config,
        .hinstance = hinstance,
        .hwnd = hwnd,
    };
}

pub fn run(self: *App) !void {
    _ = self;
    var msg: MSG = undefined;
    while (true) {
        const result = user32.GetMessageW(&msg, null, 0, 0);
        if (result == -1) {
            return windows.unexpectedError(win.kernel32.GetLastError());
        }
        if (result == 0) break;
        _ = user32.TranslateMessage(&msg);
        _ = user32.DispatchMessageW(&msg);
    }
}

pub fn terminate(self: *App) void {
    if (self.hwnd) |hwnd| {
        _ = user32.DestroyWindow(hwnd);
    }
    self.config.deinit();
}

/// Called by CoreApp to wake up the event loop.
pub fn wakeup(self: *App) void {
    if (self.hwnd) |hwnd| {
        _ = user32.PostMessageW(hwnd, WM_APP, 0, 0);
    }
}

pub fn performAction(
    self: *App,
    target: apprt.Target,
    comptime action: apprt.Action.Key,
    value: apprt.Action.Value(action),
) !bool {
    _ = target;
    _ = value;

    switch (action) {
        .quit, .close_all_windows => {
            if (self.hwnd) |hwnd| {
                _ = user32.PostMessageW(hwnd, WM_CLOSE, 0, 0);
            }
            return true;
        },
        .new_window => {
            _ = try createWindow(self.hinstance);
            return true;
        },
        else => return false,
    }
}

/// Send the given IPC to a running Ghostty. Returns `true` if the action was
/// able to be performed, `false` otherwise.
pub fn performIpc(
    alloc: std.mem.Allocator,
    target: apprt.ipc.Target,
    comptime action: apprt.ipc.Action.Key,
    value: apprt.ipc.Action.Value(action),
) !bool {
    if (comptime builtin.os.tag == .windows) {
        switch (action) {
            .new_window => return try ipc_windows.sendNewWindow(alloc, target, value),
        }
    }

    return false;
}

/// Redraw the inspector for the given surface.
pub fn redrawInspector(_: *App, _: *Surface) void {}

fn registerWindowClass(hinstance: win.HINSTANCE) !void {
    const wc = WNDCLASSEXW{
        .cbSize = @sizeOf(WNDCLASSEXW),
        .style = CS_HREDRAW | CS_VREDRAW,
        .lpfnWndProc = windowProc,
        .cbClsExtra = 0,
        .cbWndExtra = 0,
        .hInstance = hinstance,
        .hIcon = null,
        .hCursor = user32.LoadCursorW(null, IDC_ARROW),
        .hbrBackground = null,
        .lpszMenuName = null,
        .lpszClassName = class_name,
        .hIconSm = null,
    };

    if (user32.RegisterClassExW(&wc) == 0) {
        const err = win.kernel32.GetLastError();
        if (err != ERROR_CLASS_ALREADY_EXISTS) {
            return windows.unexpectedError(err);
        }
    }
}

fn createWindow(hinstance: ?win.HINSTANCE) !win.HWND {
    const hwnd = user32.CreateWindowExW(
        0,
        class_name,
        window_title,
        WS_OVERLAPPEDWINDOW | WS_VISIBLE,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        960,
        600,
        null,
        null,
        hinstance,
        null,
    ) orelse return windows.unexpectedError(win.kernel32.GetLastError());

    _ = user32.ShowWindow(hwnd, SW_SHOWDEFAULT);
    _ = user32.UpdateWindow(hwnd);
    return hwnd;
}

fn windowProc(
    hwnd: win.HWND,
    msg: win.UINT,
    wparam: win.WPARAM,
    lparam: win.LPARAM,
) callconv(.winapi) win.LRESULT {
    switch (msg) {
        WM_DESTROY => {
            user32.PostQuitMessage(0);
            return 0;
        },
        else => return user32.DefWindowProcW(hwnd, msg, wparam, lparam),
    }
}
