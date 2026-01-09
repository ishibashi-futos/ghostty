const std = @import("std");
const win = std.os.windows;

const kernel32 = struct {
    pub extern "kernel32" fn LoadLibraryW(
        lpLibFileName: win.LPCWSTR,
    ) callconv(.winapi) ?win.HMODULE;
    pub extern "kernel32" fn FreeLibrary(
        hLibModule: win.HMODULE,
    ) callconv(.winapi) win.BOOL;
    pub extern "kernel32" fn GetProcAddress(
        hModule: win.HMODULE,
        lpProcName: win.LPCSTR,
    ) callconv(.winapi) ?*anyopaque;
};

const EGLDisplay = ?*anyopaque;
const EGLContext = ?*anyopaque;
const EGLSurface = ?*anyopaque;
const EGLConfig = ?*anyopaque;
const EGLBoolean = i32;
const EGLint = i32;
const EGLNativeDisplayType = ?win.HDC;
const EGLNativeWindowType = win.HWND;

const EGL_FALSE: EGLBoolean = 0;
const EGL_TRUE: EGLBoolean = 1;
const EGL_DEFAULT_DISPLAY: EGLNativeDisplayType = null;
const EGL_NO_SURFACE: EGLSurface = null;
const EGL_NO_CONTEXT: EGLContext = null;

const EGL_NONE: EGLint = 0x3038;
const EGL_RED_SIZE: EGLint = 0x3024;
const EGL_GREEN_SIZE: EGLint = 0x3023;
const EGL_BLUE_SIZE: EGLint = 0x3022;
const EGL_ALPHA_SIZE: EGLint = 0x3021;
const EGL_DEPTH_SIZE: EGLint = 0x3025;
const EGL_STENCIL_SIZE: EGLint = 0x3026;
const EGL_SURFACE_TYPE: EGLint = 0x3033;
const EGL_WINDOW_BIT: EGLint = 0x0004;
const EGL_RENDERABLE_TYPE: EGLint = 0x3040;
const EGL_OPENGL_ES2_BIT: EGLint = 0x0004;
const EGL_CONTEXT_CLIENT_VERSION: EGLint = 0x3098;
const EGL_OPENGL_ES_API: EGLint = 0x30A0;

const Egl = struct {
    GetDisplay: *const fn (EGLNativeDisplayType) callconv(.c) EGLDisplay,
    Initialize: *const fn (EGLDisplay, *EGLint, *EGLint) callconv(.c) EGLBoolean,
    ChooseConfig: *const fn (
        EGLDisplay,
        [*]const EGLint,
        [*]EGLConfig,
        EGLint,
        *EGLint,
    ) callconv(.c) EGLBoolean,
    BindAPI: *const fn (EGLint) callconv(.c) EGLBoolean,
    CreateWindowSurface: *const fn (
        EGLDisplay,
        EGLConfig,
        EGLNativeWindowType,
        [*]const EGLint,
    ) callconv(.c) EGLSurface,
    CreateContext: *const fn (
        EGLDisplay,
        EGLConfig,
        EGLContext,
        [*]const EGLint,
    ) callconv(.c) EGLContext,
    MakeCurrent: *const fn (
        EGLDisplay,
        EGLSurface,
        EGLSurface,
        EGLContext,
    ) callconv(.c) EGLBoolean,
    SwapBuffers: *const fn (EGLDisplay, EGLSurface) callconv(.c) EGLBoolean,
    DestroySurface: *const fn (EGLDisplay, EGLSurface) callconv(.c) EGLBoolean,
    DestroyContext: *const fn (EGLDisplay, EGLContext) callconv(.c) EGLBoolean,
    Terminate: *const fn (EGLDisplay) callconv(.c) EGLBoolean,
    GetProcAddress: *const fn ([*:0]const u8) callconv(.c) ?*anyopaque,
};

pub const Context = struct {
    egl: Egl,
    egl_lib: win.HMODULE,
    gles_lib: win.HMODULE,
    display: EGLDisplay,
    surface: EGLSurface,
    context: EGLContext,

    pub fn init(hwnd: win.HWND) !Context {
        const egl_lib = kernel32.LoadLibraryW(egl_dll) orelse
            return error.EglLibraryMissing;
        errdefer _ = kernel32.FreeLibrary(egl_lib);

        const gles_lib = kernel32.LoadLibraryW(gles_dll) orelse
            return error.GlesLibraryMissing;
        errdefer _ = kernel32.FreeLibrary(gles_lib);

        const egl = try loadEgl(egl_lib);

        const display = egl.GetDisplay(EGL_DEFAULT_DISPLAY);
        if (display == null) return error.EglGetDisplayFailed;

        var major: EGLint = 0;
        var minor: EGLint = 0;
        if (egl.Initialize(display, &major, &minor) == EGL_FALSE) {
            return error.EglInitializeFailed;
        }
        errdefer _ = egl.Terminate(display);

        if (egl.BindAPI(EGL_OPENGL_ES_API) == EGL_FALSE) {
            return error.EglBindApiFailed;
        }

        var config: EGLConfig = null;
        var num_configs: EGLint = 0;
        const attribs = [_]EGLint{
            EGL_RED_SIZE, 8,
            EGL_GREEN_SIZE, 8,
            EGL_BLUE_SIZE, 8,
            EGL_ALPHA_SIZE, 8,
            EGL_DEPTH_SIZE, 24,
            EGL_STENCIL_SIZE, 8,
            EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
            EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
            EGL_NONE,
        };
        if (egl.ChooseConfig(display, &attribs, &config, 1, &num_configs) == EGL_FALSE or num_configs == 0) {
            return error.EglChooseConfigFailed;
        }

        const surface_attribs = [_]EGLint{EGL_NONE};
        const surface = egl.CreateWindowSurface(display, config, hwnd, &surface_attribs);
        if (surface == null) return error.EglCreateSurfaceFailed;
        errdefer _ = egl.DestroySurface(display, surface);

        const ctx_attribs = [_]EGLint{
            EGL_CONTEXT_CLIENT_VERSION, 2,
            EGL_NONE,
        };
        const context = egl.CreateContext(display, config, null, &ctx_attribs);
        if (context == null) return error.EglCreateContextFailed;
        errdefer _ = egl.DestroyContext(display, context);

        if (egl.MakeCurrent(display, surface, surface, context) == EGL_FALSE) {
            return error.EglMakeCurrentFailed;
        }

        return .{
            .egl = egl,
            .egl_lib = egl_lib,
            .gles_lib = gles_lib,
            .display = display,
            .surface = surface,
            .context = context,
        };
    }

    pub fn deinit(self: *Context) void {
        if (self.display != null) {
            _ = self.egl.MakeCurrent(self.display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
            if (self.context != null) {
                _ = self.egl.DestroyContext(self.display, self.context);
            }
            if (self.surface != null) {
                _ = self.egl.DestroySurface(self.display, self.surface);
            }
            _ = self.egl.Terminate(self.display);
        }
        _ = kernel32.FreeLibrary(self.gles_lib);
        _ = kernel32.FreeLibrary(self.egl_lib);
        self.* = undefined;
    }

    pub fn swapBuffers(self: *Context) void {
        _ = self.egl.SwapBuffers(self.display, self.surface);
    }

    pub fn getProcAddress(self: *const Context) *const fn ([*:0]const u8) callconv(.c) ?*anyopaque {
        return self.egl.GetProcAddress;
    }
};

const egl_dll = std.unicode.utf8ToUtf16LeStringLiteral("libEGL.dll");
const gles_dll = std.unicode.utf8ToUtf16LeStringLiteral("libGLESv2.dll");

fn loadEgl(lib: win.HMODULE) !Egl {
    return .{
        .GetDisplay = try loadFn(*const fn (EGLNativeDisplayType) callconv(.c) EGLDisplay, lib, "eglGetDisplay\x00"),
        .Initialize = try loadFn(*const fn (EGLDisplay, *EGLint, *EGLint) callconv(.c) EGLBoolean, lib, "eglInitialize\x00"),
        .ChooseConfig = try loadFn(
            *const fn (EGLDisplay, [*]const EGLint, [*]EGLConfig, EGLint, *EGLint) callconv(.c) EGLBoolean,
            lib,
            "eglChooseConfig\x00",
        ),
        .BindAPI = try loadFn(*const fn (EGLint) callconv(.c) EGLBoolean, lib, "eglBindAPI\x00"),
        .CreateWindowSurface = try loadFn(
            *const fn (EGLDisplay, EGLConfig, EGLNativeWindowType, [*]const EGLint) callconv(.c) EGLSurface,
            lib,
            "eglCreateWindowSurface\x00",
        ),
        .CreateContext = try loadFn(
            *const fn (EGLDisplay, EGLConfig, EGLContext, [*]const EGLint) callconv(.c) EGLContext,
            lib,
            "eglCreateContext\x00",
        ),
        .MakeCurrent = try loadFn(
            *const fn (EGLDisplay, EGLSurface, EGLSurface, EGLContext) callconv(.c) EGLBoolean,
            lib,
            "eglMakeCurrent\x00",
        ),
        .SwapBuffers = try loadFn(*const fn (EGLDisplay, EGLSurface) callconv(.c) EGLBoolean, lib, "eglSwapBuffers\x00"),
        .DestroySurface = try loadFn(*const fn (EGLDisplay, EGLSurface) callconv(.c) EGLBoolean, lib, "eglDestroySurface\x00"),
        .DestroyContext = try loadFn(*const fn (EGLDisplay, EGLContext) callconv(.c) EGLBoolean, lib, "eglDestroyContext\x00"),
        .Terminate = try loadFn(*const fn (EGLDisplay) callconv(.c) EGLBoolean, lib, "eglTerminate\x00"),
        .GetProcAddress = try loadFn(*const fn ([*:0]const u8) callconv(.c) ?*anyopaque, lib, "eglGetProcAddress\x00"),
    };
}

fn loadFn(comptime T: type, lib: win.HMODULE, name: [*:0]const u8) !T {
    const proc = kernel32.GetProcAddress(lib, name) orelse
        return error.EglSymbolMissing;
    return @ptrCast(proc);
}
