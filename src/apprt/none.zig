const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

const internal_os = @import("../os/main.zig");
const apprt = @import("../apprt.zig");
const ipc_windows = if (builtin.os.tag == .windows)
    @import("ipc_windows.zig")
else
    struct {};
pub const resourcesDir = internal_os.resourcesDir;

pub const App = struct {
    /// Always return false as there is no apprt to communicate with.
    pub fn performIpc(
        alloc: Allocator,
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
};
pub const Surface = struct {};
