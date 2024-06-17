const std = @import("std");
const utils = @import("utils.zig");
const mach = @import("mach");
const math = mach.math;
const gfx = mach.gfx;
const vec2 = math.vec2;
const vec3 = math.vec3;
const vec4 = math.vec4;
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;
const Mat3x3 = math.Mat3x3;
const Mat4x4 = math.Mat4x4;

pub const name = .physics;
pub const Mod = mach.Mod(@This());

pub const systems = .{
    .tick = .{ .handler = tick },
};

pub const components = .{
    // Physics
    .velocity = .{ .type = Vec2},
    .friction = .{ .type = f32},
    .invmass = .{ .type = f32},
    .wall = .{ .type = Vec4 },
    // more components
    // physics
    //      invmass
    //      friction
    //      restitution
    //      gravity
    //      shape
    //          rectangle       - x, y, w, h
    //          plane / wall    - x0, y0, nx, ny
    //          circle          - x, y, r
    //
    .rect = .{ .type = void },  // has pos, size
    .circle = .{ .type = void },  // has pos, size
    .is_contact = .{ .type = void },
    .contact_source = .{ .type = mach.EntityID },
    .contact_target = .{ .type = mach.EntityID },
    // .contact_pos ?
    // .contact_normal ?
};

fn tick(physics: *Mod, entities: *mach.Entities.Mod, delta_time: f32) !void {
    for (0..5) |_| {
        try tick_physics(physics, entities, delta_time / 5.0);
    }
}

fn tick_physics(physics: *Mod, entities: *mach.Entities.Mod, delta_time: f32) !void {
    // Physics - move ball
    var q = try entities.query(.{
        .ids = mach.Entities.Mod.read(.id),
        .size = gfx.Sprite.Mod.read(.size),
        .transform = gfx.Sprite.Mod.write(.transform),
        .velocity = Mod.write(.velocity),
        .invmass = Mod.read(.invmass),
    });
    while (q.next()) |v| {
        for (v.ids, v.size, v.transform, v.velocity, v.invmass) |obj_id, size, *transform, *velocity, invmass| {
            if (velocity.len() == 0.0) {
                continue;
            }

            const half_width = size.x() / 2.0;
            const translation = transform.*.translation();
            const x0 = translation.x() + half_width;
            const y0 = translation.y() + half_width;
            var x = x0 + velocity.x()*delta_time;
            var y = y0 + velocity.y()*delta_time;

            // Check wall boundaries
            var w_collision = try entities.query(.{
                .ids = mach.Entities.Mod.read(.id),
                .wall = Mod.read(.wall)
            });
            while (w_collision.next()) |c| {
                for (c.ids, c.wall) |col_id, wall| {
                    const w = vec2(wall.x(), wall.y());
                    const p = vec2(x, y).sub(&w);
                    const n = vec2(wall.v[2], wall.v[3]);

                    const d = p.dot(&n);
                    if (d < half_width) {
                        const vn = n.mulScalar(2.0 * velocity.dot(&n));
                        if (invmass == 0.0) { 
                            // Too heavy to bounce back
                            velocity.* = vec2(0.0, 0.0);
                        } else {
                            velocity.* = velocity.sub(&vn);
                        }
                        x += n.x() * (half_width - d);
                        y += n.y() * (half_width - d);

                        const collision = try entities.new();
                        try physics.set(collision, .is_contact, {});
                        try physics.set(collision, .contact_source, obj_id);
                        try physics.set(collision, .contact_target, col_id);
                    }
                }
            }

            // Check rectangles
            var q_collision = try entities.query(.{
                .ids = mach.Entities.Mod.read(.id),
                .size = gfx.Sprite.Mod.read(.size),
                .transform = gfx.Sprite.Mod.read(.transform),
                .rect = Mod.read(.rect),
                .velocity = Mod.read(.velocity),
                .friction = Mod.read(.friction),
            });
            while (q_collision.next()) |c| {
                for (c.ids, c.size, c.transform, c.velocity, c.friction) |col_id, col_size, col_transform, col_velocity, col_friction| {
                    if (obj_id == col_id) {
                        continue; 
                    }
                    const col_location = col_transform.translation();
                    const dx = x - col_location.x();
                    const dy = y - col_location.y();

                    if (       (dx < -half_width) 
                            or (dx > col_size.x() + half_width)
                            or (dy < -half_width)
                            or (dy > col_size.y() + half_width)) {
                        continue ;
                    }

                    var collided = false;
                    if ((dx < 0 and velocity.x() > 0) or (dx > col_size.x() and velocity.x() < 0)) {
                        velocity.* = vec2(-velocity.x(), velocity.y());
                        collided = true;
                    }
                    if ((dy < 0 and velocity.y() > 0) or (dy > col_size.y() and velocity.y() < 0)) {
                        velocity.* = vec2(velocity.x(), -velocity.y());
                        collided = true;
                    }

                    if (collided) {
                        const l = velocity.len();
                        velocity.* = velocity.add(&col_velocity.mulScalar(col_friction));
                        velocity.* = velocity.mulScalar(l / velocity.len()); // Only change direction

                        const collision = try entities.new();
                        try physics.set(collision, .is_contact, {});
                        try physics.set(collision, .contact_source, obj_id);
                        try physics.set(collision, .contact_target, col_id);
                    }
                }
            }
            transform.* = Mat4x4.translate(vec3(x - half_width, y - half_width, 0.0));
        }
    }
}