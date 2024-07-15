//!zig-autodoc-guide: docs/intro.md
//!zig-autodoc-section: Modules
//!zig-autodoc-guide: docs/app.md
//! 
const std = @import("std");
const mach = @import("mach");

/// The main application module.
pub const App = @import("App.zig");
pub const Physics = @import("Physics.zig");

// The global list of Mach modules registered for use in our application.
pub const modules = .{
    mach.Core,
    mach.Audio,
    mach.gfx.text_modules,
    mach.gfx.sprite_modules,
    App,
    Physics,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = try mach.App.init(allocator, .app);
    defer app.deinit(allocator);
    try app.run(.{ .allocator = allocator, .power_preference = .high_performance });
}
