const App = @This();

const std = @import("std");
const builtin = @import("builtin");
const win = std.os.windows;
const windows = @import("../../os/windows.zig");
const apprt = @import("../../apprt.zig");
const input = @import("../../input.zig");
const configpkg = @import("../../config.zig");
const Config = configpkg.Config;
const CoreApp = @import("../../App.zig");
const ipc_windows = @import("../ipc_windows.zig");
const Surface = @import("Surface.zig");
const render_backend_pkg = @import("render_backend.zig");

const log = std.log.scoped(.win32);

const class_name = std.unicode.utf8ToUtf16LeStringLiteral("GhosttyWin32");
const window_title = std.unicode.utf8ToUtf16LeStringLiteral("Ghostty (Win32)");

const WM_DESTROY: win.UINT = 0x0002;
const WM_SIZE: win.UINT = 0x0005;
const WM_SETFOCUS: win.UINT = 0x0007;
const WM_KILLFOCUS: win.UINT = 0x0008;
const WM_CLOSE: win.UINT = 0x0010;
const WM_KEYDOWN: win.UINT = 0x0100;
const WM_KEYUP: win.UINT = 0x0101;
const WM_CHAR: win.UINT = 0x0102;
const WM_SYSKEYDOWN: win.UINT = 0x0104;
const WM_SYSKEYUP: win.UINT = 0x0105;
const WM_MOUSEMOVE: win.UINT = 0x0200;
const WM_LBUTTONDOWN: win.UINT = 0x0201;
const WM_LBUTTONUP: win.UINT = 0x0202;
const WM_RBUTTONDOWN: win.UINT = 0x0204;
const WM_RBUTTONUP: win.UINT = 0x0205;
const WM_MBUTTONDOWN: win.UINT = 0x0207;
const WM_MBUTTONUP: win.UINT = 0x0208;
const WM_MOUSEWHEEL: win.UINT = 0x020A;
const WM_APP: win.UINT = 0x8000;
const WM_DPICHANGED: win.UINT = 0x02E0;
const CS_HREDRAW: win.UINT = 0x0002;
const CS_VREDRAW: win.UINT = 0x0001;
const WS_OVERLAPPEDWINDOW: win.DWORD = 0x00CF0000;
const WS_VISIBLE: win.DWORD = 0x10000000;
const CW_USEDEFAULT: win.INT = @bitCast(@as(u32, 0x80000000));
const SW_SHOWDEFAULT: win.INT = 10;
const SWP_NOZORDER: win.UINT = 0x0004;
const SWP_NOACTIVATE: win.UINT = 0x0010;
const ERROR_CLASS_ALREADY_EXISTS: win.Win32Error = .CLASS_ALREADY_EXISTS;
const IDC_ARROW: win.LPCWSTR = @ptrFromInt(@as(usize, 32512));
const GWLP_USERDATA: win.INT = -21;
const DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2: win.HANDLE = @ptrFromInt(
    @as(usize, @bitCast(@as(isize, -4))),
);

const VK_SHIFT: win.INT = 0x10;
const VK_CONTROL: win.INT = 0x11;
const VK_MENU: win.INT = 0x12;
const VK_LWIN: win.INT = 0x5B;
const VK_RWIN: win.INT = 0x5C;
const VK_CAPITAL: win.INT = 0x14;
const VK_NUMLOCK: win.INT = 0x90;
const VK_BACK: win.INT = 0x08;
const VK_TAB: win.INT = 0x09;
const VK_RETURN: win.INT = 0x0D;
const VK_ESCAPE: win.INT = 0x1B;
const VK_PRIOR: win.INT = 0x21;
const VK_NEXT: win.INT = 0x22;
const VK_END: win.INT = 0x23;
const VK_HOME: win.INT = 0x24;
const VK_LEFT: win.INT = 0x25;
const VK_UP: win.INT = 0x26;
const VK_RIGHT: win.INT = 0x27;
const VK_DOWN: win.INT = 0x28;
const VK_INSERT: win.INT = 0x2D;
const VK_DELETE: win.INT = 0x2E;
const VK_F1: win.INT = 0x70;
const VK_F24: win.INT = 0x87;

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

const RECT = extern struct {
    left: win.LONG,
    top: win.LONG,
    right: win.LONG,
    bottom: win.LONG,
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
    pub extern "user32" fn SetProcessDpiAwarenessContext(
        value: win.HANDLE,
    ) callconv(.winapi) win.BOOL;
    pub extern "user32" fn SetWindowPos(
        hWnd: win.HWND,
        hWndInsertAfter: ?win.HWND,
        X: win.INT,
        Y: win.INT,
        cx: win.INT,
        cy: win.INT,
        uFlags: win.UINT,
    ) callconv(.winapi) win.BOOL;
    pub extern "user32" fn SetWindowLongPtrW(
        hWnd: win.HWND,
        nIndex: win.INT,
        dwNewLong: win.LONG_PTR,
    ) callconv(.winapi) win.LONG_PTR;
    pub extern "user32" fn GetWindowLongPtrW(
        hWnd: win.HWND,
        nIndex: win.INT,
    ) callconv(.winapi) win.LONG_PTR;
    pub extern "user32" fn GetKeyState(
        nVirtKey: win.INT,
    ) callconv(.winapi) win.SHORT;
};

core_app: *CoreApp,
config: Config,
render_backend: render_backend_pkg.Backend,
hinstance: ?win.HINSTANCE = null,
hwnd: ?win.HWND = null,
surface: ?*Surface = null,

pub fn init(
    self: *App,
    core_app: *CoreApp,
    opts: struct {},
) !void {
    _ = opts;
    if (comptime builtin.os.tag != .windows) return error.UnsupportedPlatform;

    const config = try Config.default(core_app.alloc);

    const hmodule = kernel32.GetModuleHandleW(null) orelse
        return windows.unexpectedError(win.kernel32.GetLastError());

    const hinstance: win.HINSTANCE = @ptrCast(hmodule);
    self.* = .{
        .core_app = core_app,
        .config = config,
        .render_backend = render_backend_pkg.selectDefault(),
        .hinstance = hinstance,
        .hwnd = null,
        .surface = null,
    };
    errdefer self.config.deinit();
    log.info("win32 renderer backend={s}", .{@tagName(self.render_backend)});

    _ = user32.SetProcessDpiAwarenessContext(
        DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2,
    );
    try registerWindowClass(hinstance);
    const hwnd = try createWindow(self);
    self.hwnd = hwnd;
}

pub fn run(self: *App) !void {
    var msg: MSG = undefined;
    while (true) {
        const result = user32.GetMessageW(&msg, null, 0, 0);
        if (result == -1) {
            return windows.unexpectedError(win.kernel32.GetLastError());
        }
        if (result == 0) break;
        _ = user32.TranslateMessage(&msg);
        _ = user32.DispatchMessageW(&msg);
        if (msg.message == WM_APP) {
            try self.core_app.tick(self);
        }
    }
}

pub fn terminate(self: *App) void {
    if (self.hwnd) |hwnd| {
        _ = user32.DestroyWindow(hwnd);
        self.hwnd = null;
    }
    if (self.surface) |surface| {
        surface.deinit();
        self.core_app.alloc.destroy(surface);
        self.surface = null;
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
            _ = try createWindow(self);
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

fn createWindow(app: *App) !win.HWND {
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
        app.hinstance,
        null,
    ) orelse return windows.unexpectedError(win.kernel32.GetLastError());

    _ = user32.SetWindowLongPtrW(hwnd, GWLP_USERDATA, @intCast(@intFromPtr(app)));
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
    const app = getAppFromWindow(hwnd);
    switch (msg) {
        WM_CLOSE => {
            _ = user32.DestroyWindow(hwnd);
            return 0;
        },
        WM_SETFOCUS, WM_KILLFOCUS => {
            if (app) |app_ptr| {
                const focused = msg == WM_SETFOCUS;
                app_ptr.core_app.focusEvent(focused);
                if (app_ptr.surface) |surface| {
                    surface.core().focusCallback(focused) catch |err| {
                        log.err("focus callback failed err={}", .{err});
                    };
                }
            }
            return 0;
        },
        WM_SIZE, WM_MOUSEMOVE, WM_LBUTTONDOWN, WM_LBUTTONUP, WM_RBUTTONDOWN, WM_RBUTTONUP, WM_MBUTTONDOWN, WM_MBUTTONUP, WM_MOUSEWHEEL, WM_KEYDOWN, WM_KEYUP, WM_SYSKEYDOWN, WM_SYSKEYUP, WM_CHAR => {
            if (app) |app_ptr| {
                if (app_ptr.handleInputMessage(hwnd, msg, wparam, lparam)) {
                    return 0;
                }
            }
        },
        WM_DPICHANGED => {
            const rect_ptr: *const RECT = @ptrFromInt(
                @as(usize, @bitCast(lparam)),
            );
            _ = user32.SetWindowPos(
                hwnd,
                null,
                rect_ptr.left,
                rect_ptr.top,
                rect_ptr.right - rect_ptr.left,
                rect_ptr.bottom - rect_ptr.top,
                SWP_NOZORDER | SWP_NOACTIVATE,
            );
            return 0;
        },
        WM_DESTROY => {
            user32.PostQuitMessage(0);
            return 0;
        },
        else => {},
    }

    return user32.DefWindowProcW(hwnd, msg, wparam, lparam);
}

fn createSurface(app: *App) !*Surface {
    var surface = try app.core_app.alloc.create(Surface);
    errdefer app.core_app.alloc.destroy(surface);

    var config = try apprt.surface.newConfig(app.core_app, &app.config, .window);
    defer config.deinit();

    try surface.init(app, &config);
    errdefer surface.deinit();

    return surface;
}

fn getAppFromWindow(hwnd: win.HWND) ?*App {
    const ptr = user32.GetWindowLongPtrW(hwnd, GWLP_USERDATA);
    if (ptr == 0) return null;
    return @ptrFromInt(@as(usize, @intCast(ptr)));
}

fn handleInputMessage(
    self: *App,
    hwnd: win.HWND,
    msg: win.UINT,
    wparam: win.WPARAM,
    lparam: win.LPARAM,
) bool {
    _ = hwnd;
    const surface = self.surface orelse return false;
    switch (msg) {
        WM_SIZE => {
            const width = @as(u32, @intCast(@as(u16, @truncate(@as(u64, @bitCast(lparam))))));
            const height = @as(u32, @intCast(@as(u16, @truncate(@as(u64, @bitCast(lparam)) >> 16))));
            surface.core().sizeCallback(.{
                .width = width,
                .height = height,
            }) catch |err| log.err("size callback failed err={}", .{err});
            return true;
        },
        WM_MOUSEMOVE => {
            const x = @as(i16, @bitCast(@as(u16, @truncate(@as(u64, @bitCast(lparam))))));
            const y = @as(i16, @bitCast(@as(u16, @truncate(@as(u64, @bitCast(lparam)) >> 16))));
            surface.core().cursorPosCallback(.{
                .x = @floatFromInt(x),
                .y = @floatFromInt(y),
            }, getMods()) catch |err| log.err("cursor move failed err={}", .{err});
            return true;
        },
        WM_LBUTTONDOWN, WM_LBUTTONUP, WM_RBUTTONDOWN, WM_RBUTTONUP, WM_MBUTTONDOWN, WM_MBUTTONUP => {
            const action: input.MouseButtonState = switch (msg) {
                WM_LBUTTONDOWN, WM_RBUTTONDOWN, WM_MBUTTONDOWN => .press,
                else => .release,
            };
            const button: input.MouseButton = switch (msg) {
                WM_LBUTTONDOWN, WM_LBUTTONUP => .left,
                WM_RBUTTONDOWN, WM_RBUTTONUP => .right,
                else => .middle,
            };
            const handled = surface.core().mouseButtonCallback(
                action,
                button,
                getMods(),
            ) catch |err| {
                log.err("mouse button failed err={}", .{err});
                return true;
            };
            return handled;
        },
        WM_MOUSEWHEEL => {
            const delta = @as(i16, @bitCast(@as(u16, @truncate(@as(u64, @bitCast(wparam)) >> 16))));
            const yoff: f64 = @as(f64, @floatFromInt(delta)) / 120.0;
            surface.core().scrollCallback(0, yoff, .{}) catch |err| {
                log.err("scroll failed err={}", .{err});
            };
            return true;
        },
        WM_KEYDOWN, WM_KEYUP, WM_SYSKEYDOWN, WM_SYSKEYUP => {
            const action: input.Action = switch (msg) {
                WM_KEYUP, WM_SYSKEYUP => .release,
                else => if ((@as(u64, @bitCast(lparam)) & (1 << 30)) != 0)
                    .repeat
                else
                    .press,
            };
            const vk = @as(win.INT, @intCast(wparam));
            const scancode = scanCodeFromLparam(lparam);
            const key = mapScanCode(scancode) orelse mapVirtualKey(vk) orelse return false;
            const event: input.KeyEvent = .{
                .action = action,
                .key = key,
                .mods = getMods(),
            };
            _ = surface.core().keyCallback(event) catch |err| {
                log.err("key callback failed err={}", .{err});
                return true;
            };
            return true;
        },
        WM_CHAR => {
            const codepoint = @as(u21, @intCast(wparam));
            if (codepoint < 0x20) return false;
            var buf: [4]u8 = undefined;
            const len = std.unicode.utf8Encode(codepoint, buf[0..]) catch return false;
            const event: input.KeyEvent = .{
                .action = .press,
                .key = .unidentified,
                .mods = getMods(),
                .utf8 = buf[0..len],
                .unshifted_codepoint = codepoint,
            };
            _ = surface.core().keyCallback(event) catch |err| {
                log.err("text key callback failed err={}", .{err});
                return true;
            };
            return true;
        },
        else => return false,
    }
}

fn getMods() input.Mods {
    return .{
        .shift = keyPressed(VK_SHIFT),
        .ctrl = keyPressed(VK_CONTROL),
        .alt = keyPressed(VK_MENU),
        .super = keyPressed(VK_LWIN) or keyPressed(VK_RWIN),
        .caps_lock = keyToggled(VK_CAPITAL),
        .num_lock = keyToggled(VK_NUMLOCK),
    };
}

fn keyPressed(vk: win.INT) bool {
    const state = @as(u16, @bitCast(user32.GetKeyState(vk)));
    return (state & 0x8000) != 0;
}

fn keyToggled(vk: win.INT) bool {
    const state = @as(u16, @bitCast(user32.GetKeyState(vk)));
    return (state & 0x0001) != 0;
}

fn mapVirtualKey(vk: win.INT) ?input.Key {
    return switch (vk) {
        VK_BACK => .backspace,
        VK_TAB => .tab,
        VK_RETURN => .enter,
        VK_ESCAPE => .escape,
        VK_PRIOR => .page_up,
        VK_NEXT => .page_down,
        VK_END => .end,
        VK_HOME => .home,
        VK_LEFT => .arrow_left,
        VK_UP => .arrow_up,
        VK_RIGHT => .arrow_right,
        VK_DOWN => .arrow_down,
        VK_INSERT => .insert,
        VK_DELETE => .delete,
        VK_F1...VK_F24 => {
            const base = @intFromEnum(input.Key.f1);
            const offset: @TypeOf(base) = @intCast(vk - VK_F1);
            return @enumFromInt(base + offset);
        },
        else => null,
    };
}

fn scanCodeFromLparam(lparam: win.LPARAM) u32 {
    const raw = @as(u32, @intCast((@as(usize, @bitCast(lparam)) >> 16) & 0xFF));
    const extended = ((@as(usize, @bitCast(lparam)) >> 24) & 0x01) != 0;
    return if (extended) raw | 0xE000 else raw;
}

fn mapScanCode(scancode: u32) ?input.Key {
    for (input.keycodes.entries) |entry| {
        if (entry.native == scancode) return entry.key;
    }
    return null;
}
