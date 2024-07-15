const std = @import("std");
const mach = @import("mach");
const gfx = mach.gfx;
const math = mach.math;
const vec2 = math.vec2;
const vec3 = math.vec3;
const vec4 = math.vec4;
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;
const Mat3x3 = math.Mat3x3;
const Mat4x4 = math.Mat4x4;
const zigimg = @import("zigimg");
const gpu = mach.gpu;
pub const name = .app;

pub fn loadTexture(filename: []const u8, core: *mach.Core.Mod, allocator: std.mem.Allocator) !*gpu.Texture {
    const device = core.state().device;
    const queue = core.state().queue;

    // Load the image from memory
    var img = try zigimg.Image.fromFilePath(allocator, filename);
    defer img.deinit();
    const img_size = gpu.Extent3D{ .width = @as(u32, @intCast(img.width)), .height = @as(u32, @intCast(img.height)) };

    // Create a GPU texture
    const label = @tagName(name) ++ ".loadTexture";
    const texture = device.createTexture(&.{
        .label = label,
        .size = img_size,
        .format = .rgba8_unorm,
        .usage = .{
            .texture_binding = true,
            .copy_dst = true,
        },
    });
    const data_layout = gpu.Texture.DataLayout{
        .bytes_per_row = @as(u32, @intCast(img.width * 4)),
        .rows_per_image = @as(u32, @intCast(img.height)),
    };
    switch (img.pixels) {
        .rgba32 => |pixels| queue.writeTexture(&.{ .texture = texture }, &data_layout, &img_size, pixels),
        .rgb24 => |pixels| {
            const data = try rgb24ToRgba32(allocator, pixels);
            defer data.deinit(allocator);
            queue.writeTexture(&.{ .texture = texture }, &data_layout, &img_size, data.rgba32);
        },
        else => @panic("unsupported image color format"),
    }
    return texture;
}

fn rgb24ToRgba32(allocator: std.mem.Allocator, in: []zigimg.color.Rgb24) !zigimg.color.PixelStorage {
    const out = try zigimg.color.PixelStorage.init(allocator, .rgba32, in.len);
    var i: usize = 0;
    while (i < in.len) : (i += 1) {
        out.rgba32[i] = zigimg.color.Rgba32{ .r = in[i].r, .g = in[i].g, .b = in[i].b, .a = 255 };
    }
    return out;
}

pub fn createText(entities: *mach.Entities.Mod, 
    text: *gfx.Text.Mod,
    pipeline_entity: mach.EntityID, 
    style: mach.EntityID, 
    x: f32,
    y: f32,
    comptime fmt: []const u8, 
    args: anytype
) !mach.EntityID {
    // Create some text
    const text_entity = try entities.new();
    try text.set(text_entity, .pipeline, pipeline_entity);
    try text.set(text_entity, .transform, Mat4x4.translate(vec3(x, y, 0)));
    try gfx.Text.allocPrintText( text, text_entity, style, fmt, args);

    return text_entity;
}

pub fn updateText(text: *gfx.Text.Mod,    
    text_entity: mach.EntityID,
    comptime fmt: []const u8, 
    args: anytype
) !void {
    const styles = text.get(text_entity, .style).?;
    try gfx.Text.allocPrintText(text, text_entity, styles[0], fmt, args);
}
