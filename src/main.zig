//!zig-autodoc-guide: docs/intro.md
//!zig-autodoc-section: Modules
//!zig-autodoc-guide: docs/app.md
//! 

const std = @import("std");
const mach = @import("mach");

/// The main application module.
pub const App = @import("App.zig");

// The global list of Mach modules registered for use in our application.
pub const modules = .{
    mach.Core,
    mach.Audio,
    mach.gfx.text_modules,
    mach.gfx.sprite_modules,
    App,
};

// TODO(important): use standard entrypoint instead
pub fn main() !void {
    const a = .hello;
    std.debug.print("{}", .{a});
    // Initialize mach.Core
    try mach.core.initModule();

    // Main loop
    while (try mach.core.tick()) {}
}
