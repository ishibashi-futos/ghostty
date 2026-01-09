const std = @import("std");
const win = std.os.windows;

const kernel32 = struct {
    pub extern "kernel32" fn LoadLibraryW(
        lpLibFileName: win.LPCWSTR,
    ) callconv(.winapi) ?win.HMODULE;
    pub extern "kernel32" fn FreeLibrary(
        hLibModule: win.HMODULE,
    ) callconv(.winapi) win.BOOL;
};

pub const Backend = enum {
    angle,
    vulkan,
    wgl,
};

pub const Availability = struct {
    angle: bool,
    vulkan: bool,
    wgl: bool,
};

pub fn detectAvailability() Availability {
    const angle = dllAvailable(angle_egl) and dllAvailable(angle_gles);
    const vulkan = dllAvailable(vulkan_loader);
    const wgl = dllAvailable(opengl32);
    return .{ .angle = angle, .vulkan = vulkan, .wgl = wgl };
}

pub fn selectDefault() Backend {
    const availability = detectAvailability();
    if (availability.angle) return .angle;
    if (availability.vulkan) return .vulkan;
    return .wgl;
}

const angle_egl = std.unicode.utf8ToUtf16LeStringLiteral("libEGL.dll");
const angle_gles = std.unicode.utf8ToUtf16LeStringLiteral("libGLESv2.dll");
const vulkan_loader = std.unicode.utf8ToUtf16LeStringLiteral("vulkan-1.dll");
const opengl32 = std.unicode.utf8ToUtf16LeStringLiteral("opengl32.dll");

fn dllAvailable(name: [:0]const u16) bool {
    const handle = kernel32.LoadLibraryW(name) orelse return false;
    _ = kernel32.FreeLibrary(handle);
    return true;
}
