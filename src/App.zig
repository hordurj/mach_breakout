const std = @import("std");
const mach = @import("mach");
const zigimg = @import("zigimg");
const utils = @import("utils.zig");
const Physics = @import("Physics.zig");
const gpu = mach.gpu;
const gfx = mach.gfx;
const math = mach.math;
const sysaudio = mach.sysaudio;

const SpritePipeline = gfx.SpritePipeline;
const Sprite = gfx.Sprite;

const sprs = @import("SpriteSheet.zig");
const SpriteSheet = sprs.SpriteSheet;

const vec2 = math.vec2;
const vec3 = math.vec3;
const vec4 = math.vec4;
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;
const Mat3x3 = math.Mat3x3;
const Mat4x4 = math.Mat4x4;

const GameState = enum {
    ready,
    playing,
    game_over,
    paused
};

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

// Game state and visuals
game_state: GameState = .ready,
player: mach.EntityID,
ball: mach.EntityID = undefined,
floor: mach.EntityID = undefined,
score: u32,
score_text: mach.EntityID,
high_score: u32,
high_score_text: mach.EntityID,
info_text: mach.EntityID,
bricks_left: u32 = 0,
level: u32 = 1,
lives_left: u32 = 3,
lives_balls: [2] mach.EntityID,

// Game config
paddle_speed: f32 = 400,
ball_speed: f32 = 200,
width: f32 = 960.0,         // Width of render area - will be scaled to window
height: f32 = 540.0,        // Height of render area - will be scaled to window

// Resources
allocator: std.mem.Allocator,
pipeline: mach.EntityID,
background_pipeline: mach.EntityID,
text_pipeline: mach.EntityID,
frame_encoder: *gpu.CommandEncoder = undefined,
frame_render_pass: *gpu.RenderPassEncoder = undefined,
spritesheet: SpriteSheet = undefined,
impact_sfx: mach.Audio.Opus = undefined,

// Diagnostics
timer: mach.Timer,
fps_timer: mach.Timer,
frame_count: usize,
rand: std.rand.DefaultPrng,
time: f32,

pub const name = .app;
pub const Mod = mach.Mod(@This());

pub const systems = .{
    .init = .{ .handler = init },
    .deinit = .{ .handler = deinit },
    .after_init = .{ .handler = afterInit },
    .tick = .{ .handler = tick },

    .inputs = .{ .handler = tick_inputs },
    .game_logic = .{ .handler = tick_game_logic },
    .render = .{ .handler = tick_render },
    .audio_state_change = .{ .handler = audioStateChange },
    .end_frame = .{ .handler = endFrame },
};

pub const components = .{
    .is_bgm = .{ .type = void },                // Tags the background music
    .is_hittable = .{ .type = void},            // Breakable objects
    .parent = .{ .type = mach.EntityID },       // If parent is self then 
    .local_transform = .{ .type = Mat4x4 },     // Transform relative to parent
    .health = .{ .type = u32 },                 // Not used atm - can be used for multi hit bricks
    .reward = .{ .type = u32 },                 // Reward per brick
    .score = .{ .type = u32 },                  // Track score in player entity
    .lives = .{ .type = u8 },                   // Track lives left in player entity
};

// States (how to manage)
//      init
//      intro screen    *
//      game            *
//      game over       *
//      new level   
//      deinit
//

// ------ Notes -----
//     Should a system go into its own module or not?
//     How can modules / systems be made generic such they can support different component types.
//          E.g. a physics and a sprite manager use a location. If the sprite manager defines location
//          does the physics engine need to depend on that?
//
//      One approach is to have a core system with common types
//
//      When a system is created should it define its query criteria? 
//      It could help optimize the query as the query could be prepared 
//      beforehand and make hints for data organization, etc.
//
//      Spatial indexing? Could add components for different section of screen
//          or build in index schemes, e.g. r-tree, quad-tree,
//

fn buildLevel(
    spritesheet: *SpriteSheet,
    pipeline: mach.EntityID,
    entities: *mach.Entities.Mod,
    sprite: *Sprite.Mod,
    game: *Mod,
    physics: *Physics.Mod,
) !void {
    // Get window height and width
    const width: f32 = game.state().width; 
    const height: f32 = game.state().height;

    const board_height_fraction: f32 = 0.6; 

    const padding_x: f32 = width * 0.05;
    const padding_y: f32 = height * 0.18;

    const brick_padding_x: f32 = 5.0;
    const brick_padding_y: f32 = 5.0;

    // Bricks
    const blue_brick_sprite = spritesheet.get("core_0_Layer 0").?;
    const green_brick_sprite = spritesheet.get("core_1_Layer 0").?;
    const red_brick_sprite = spritesheet.get("core_2_Layer 0").?;

    const brick_sprite = [3]sprs.Sprite{
        blue_brick_sprite,
        green_brick_sprite,
        red_brick_sprite
    };

    const brick_reward = [3]u32{ 100, 50, 25 };

    const w: f32 = @floatFromInt(brick_sprite[0].source[2]);
    const h: f32 = @floatFromInt(brick_sprite[0].source[3]);

    const cols: usize = @intFromFloat((width - 2.0 * padding_x) / (w + brick_padding_x));
    const rows: usize = @intFromFloat((height * board_height_fraction - 2.0 * padding_y) / (h + brick_padding_y));

    const offset_x: f32 = -width / 2.0 + padding_x; // Center on screen
    const offset_y: f32 = height / 2.0 - padding_y;

    const x0:f32 = offset_x;
    const y0:f32 = offset_y;

    var number_of_bricks: u32 = 0;

    for (0..rows) |i| {
        const iy:f32 = @floatFromInt(i);
        for (0..cols) |j| {
            const jx:f32 = @floatFromInt(j);

            const brick = try entities.new();
            const x_pos = x0+jx*(w+brick_padding_x);
            const y_pos = y0-iy*(h+brick_padding_y);
            try sprite.set(brick, .transform, Mat4x4.translate(
                vec3(x_pos, y_pos, 0.0)));

            const k = (brick_sprite.len * i) / rows;
            const x: f32 = @floatFromInt(brick_sprite[k].source[0]);
            const y: f32 = @floatFromInt(brick_sprite[k].source[1]);

            try sprite.set(brick, .size, vec2(w, h));
            try sprite.set(brick, .uv_transform, Mat3x3.translate(vec2(x, y)));
            try sprite.set(brick, .pipeline, pipeline);
            try physics.set(brick, .velocity, vec2(0.0, 0.0));
            try physics.set(brick, .friction, 0.0);
            try physics.set(brick, .invmass, 0.0);
            try physics.set(brick, .rect, {});
            try game.set(brick, .is_hittable, {});
            try game.set(brick, .reward, brick_reward[k]);
            number_of_bricks += 1;
        }
    }
    game.state().bricks_left = number_of_bricks;
}

fn deinit(
    core: *mach.Core.Mod,
    sprite_pipeline: *SpritePipeline.Mod,
    audio: *mach.Audio.Mod,    
    game: *Mod,
) !void {
    sprite_pipeline.schedule(.deinit);
    audio.schedule(.deinit);
    core.schedule(.deinit);

    game.state().spritesheet.deinit();
}
fn init(
    entities: *mach.Entities.Mod,
    core: *mach.Core.Mod,
    sprite_pipeline: *SpritePipeline.Mod,
    text: *gfx.Text.Mod,
    text_pipeline: *gfx.TextPipeline.Mod,
    audio: *mach.Audio.Mod,    
    game: *Mod,
) !void {
    try core.set(core.state().main_window, .fullscreen, false);

    core.schedule(.init);
    sprite_pipeline.schedule(.init);    
    text.schedule(.init);
    text_pipeline.schedule(.init);
    audio.schedule(.init);

    {
        const file = try std.fs.cwd().openFile(
            "assets/background_music.opus", 
            .{.mode = .read_only});
        defer file.close();

        const bgm_sound_stream = std.io.StreamSource{ .file = file };
        const bgm = try mach.Audio.Opus.decodeStream(gpa.allocator(), bgm_sound_stream);

        const bgm_entity = try entities.new();
        try game.set(bgm_entity, .is_bgm, {});
        try audio.set(bgm_entity, .samples, bgm.samples);
        try audio.set(bgm_entity, .channels, bgm.channels);
        try audio.set(bgm_entity, .playing, true);
        try audio.set(bgm_entity, .index, 0);
    }

    game.schedule(.after_init);
}

fn afterInit(
    entities: *mach.Entities.Mod,
    core: *mach.Core.Mod,
    sprite: *Sprite.Mod,
    sprite_pipeline: *SpritePipeline.Mod,
    audio: *mach.Audio.Mod,
    text: *gfx.Text.Mod,
    text_pipeline: *gfx.TextPipeline.Mod,
    text_style: *gfx.TextStyle.Mod,
    game: *Mod,
    physics: *Physics.Mod,
) !void {
    const allocator = gpa.allocator();

    // Read in sheet map
    var spritesheet = SpriteSheet.init(allocator);

    try sprs.loadPixiSpriteAtlas(
        allocator, "assets/gameobjects.atlas", 
        &spritesheet);

    // Background
    const background_pipeline = try entities.new();
    try sprite_pipeline.set(background_pipeline, .texture, try utils.loadTexture("assets/background.png",core, allocator));

    const pipeline = try entities.new();
    try sprite_pipeline.set(pipeline, .texture, try utils.loadTexture("assets/gameobjects.png", core, allocator));

    const player = try entities.new();
    const ball = try entities.new();
    const bottom_wall = try entities.new();

    // Text
    const style1 = try entities.new();
    try text_style.set(style1, .font_size, 48 * gfx.px_per_pt); // 48pt
    try text_style.set(style1, .font_color, vec4(1.0, 0.8, 0.0, 1.0)); // yellow

    const style_large = try entities.new();
    try text_style.set(style_large, .font_size, 100 * gfx.px_per_pt);
    try text_style.set(style_large, .font_color, vec4(0.0, 0.8, 1.0, 1.0)); 

    // Create a text rendering pipeline
    const text_pipeline_entity = try entities.new();
    try text_pipeline.set(text_pipeline_entity, .is_pipeline, {});
    text_pipeline.schedule(.update);

    game.init(.{
        .timer = try mach.Timer.start(),
        .player = player,
        .ball = ball,
        .floor = bottom_wall,
        .fps_timer = try mach.Timer.start(),
        .frame_count = 0,
        .rand = std.rand.DefaultPrng.init(1337),
        .time = 0,
        .allocator = allocator,
        .pipeline = pipeline,
        .background_pipeline = background_pipeline,
        .text_pipeline = text_pipeline_entity,
        .spritesheet = spritesheet,
        .score = 0,
        .score_text = undefined,
        .high_score = 0,
        .high_score_text = undefined,
        .info_text = undefined,
        .lives_left = 3,
        .lives_balls = undefined
    });

    const width: f32 = game.state().width; 
    const height: f32 = game.state().height;

    // Player
    {
        // TOOD: helper to set sprite components using a spritesheet.
        const player_sprite_left = spritesheet.get("core_64_Layer 0").?;
        const player_sprite_right = spritesheet.get("core_65_Layer 0").?;
        const x: f32 = @floatFromInt(player_sprite_left.source[0]);
        const y: f32 = @floatFromInt(player_sprite_left.source[1]);
        const w: f32 = @floatFromInt(player_sprite_left.source[2] + player_sprite_right.source[2]);
        const h: f32 = @floatFromInt(player_sprite_left.source[3]);

        try sprite.set(player, .transform, Mat4x4.translate(vec3(0.0, -height/2.0*0.9, 0.0)));
        try physics.set(player, .velocity, vec2(0.0, 0.0));
        try physics.set(player, .friction, 0.5);
        try physics.set(player, .invmass, 0.0);
        try physics.set(player, .rect, {});
        try sprite.set(player, .size, vec2(w, h));
        try sprite.set(player, .uv_transform, Mat3x3.translate(vec2(x, y)));
        try sprite.set(player, .pipeline, pipeline);
    }

    // Ball
    const ball_sprite = spritesheet.get("core_32_Layer 0").?;
    const x: f32 = @floatFromInt(ball_sprite.source[0]);
    const y: f32 = @floatFromInt(ball_sprite.source[1]);
    const w: f32 = @floatFromInt(ball_sprite.source[2]);
    const h: f32 = @floatFromInt(ball_sprite.source[3]);

    try sprite.set(ball, .transform, Mat4x4.translate(vec3(-100.0, -height/2.0*0.5, 0.0)));
    try sprite.set(ball, .size, vec2(w, h));
    try sprite.set(ball, .uv_transform, Mat3x3.translate(vec2(x, y)));
    try sprite.set(ball, .pipeline, pipeline);
    try physics.set(ball, .velocity, vec2(0.0, 0.0));
    try physics.set(ball, .friction, 0.0);
    try physics.set(ball, .invmass, 1.0);

    try game.set(ball, .parent, player);
    try game.set(ball, .local_transform, Mat4x4.translate(vec3(32.0, 12, 0.0)));

    // Walls
    const top_wall = try entities.new();
    try physics.set(top_wall, .wall, vec4(0.0, height / 2, 0.0, -1.0));
    try physics.set(top_wall, .friction, 0.0);
    try physics.set(top_wall, .invmass, 0.0);

    try physics.set(bottom_wall, .wall, vec4(0.0, -height / 2, 0.0, 1.0));
    try physics.set(bottom_wall, .friction, 0.0);
    try physics.set(bottom_wall, .invmass, 0.0);

    const left_wall = try entities.new();
    try physics.set(left_wall, .wall, vec4(-width / 2.0, 0.0, 1.0, 0.0));
    try physics.set(left_wall, .friction, 0.0);
    try physics.set(left_wall, .invmass, 0.0);

    const right_wall = try entities.new();
    try physics.set(right_wall, .wall, vec4(width / 2.0, 0.0, -1.0, 0.0));
    try physics.set(right_wall, .friction, 0.0);
    try physics.set(right_wall, .invmass, 0.0);

    const background = try entities.new();
    try sprite.set(background, .transform, Mat4x4.translate(
        vec3(-width/2, -height/2, 0.0)));
    try sprite.set(background, .size, vec2(1152, 896));
    try sprite.set(background, .uv_transform, Mat3x3.translate(vec2(0, 0)));
    try sprite.set(background, .pipeline, background_pipeline);

    sprite_pipeline.schedule(.update);
    sprite.schedule(.update);

    // Create some text
    game.state().score_text = try utils.createText(entities, text, text_pipeline_entity, style1, 
        -width/2 + 20, height/2 - 30, 
        \\ Score \n 0
    , .{});

    game.state().high_score_text = try utils.createText(entities, text, text_pipeline_entity, style1, 
        0.0, height/2 - 30, 
        \\ High Score \n 0
    , .{});

    game.state().info_text = try utils.createText(entities, text, text_pipeline_entity, style_large, 
        -280.0, -50.0, 
        \\ Press any key to start
    , .{});

    text.schedule(.update);

    try buildLevel(&spritesheet, pipeline, entities, sprite, game, physics);

    // Lives
    var x_pos: f32 = -width / 2.0 + 20;
    for (0..game.state().lives_left-1) |i| {
        const ball_live = try entities.new();
        game.state().lives_balls[i] = ball_live;

        try sprite.set(ball_live, .transform, Mat4x4.translate(vec3(x_pos, -height/2.0+10.0, 0.0)));
        try sprite.set(ball_live, .size, vec2(w, h));
        try sprite.set(ball_live, .uv_transform, Mat3x3.translate(vec2(x, y)));
        try sprite.set(ball_live, .pipeline, pipeline);

        x_pos += 20.0;
    }

    {
        const file = try std.fs.cwd().openFile(
            "assets/impact-152508.opus", 
            .{.mode = .read_only});
        defer file.close();

        const impact_sound_stream = std.io.StreamSource{ .file = file };
        game.state().impact_sfx = try mach.Audio.Opus.decodeStream(gpa.allocator(), impact_sound_stream);
    }

    audio.state().on_state_change = game.system(.audio_state_change);
    core.schedule(.start);    
}

fn tick_inputs(game: *Mod, physics: *Physics.Mod, core: *mach.Core.Mod) !void {
    var iter = mach.core.pollEvents();
    var velocity = physics.get(game.state().player, .velocity).?;
    const speed = game.state().paddle_speed;

    // Handle inputs
    while (iter.next()) |event| {
        switch (event) {
            .key_press => |ev| {
                switch (ev.key) {
                    .escape, .q => core.schedule(.exit),
                    else => {},
                }

                switch (game.state().game_state) {                    
                    // TODO: move into a state machine that can receive events for transitions.
                    .playing => {
                        switch (ev.key) {
                            .escape => core.schedule(.exit),
                            .left => velocity.v[0] = -speed,
                            .right => velocity.v[0] = speed,
                            .space => {
                                const ball_parent = game.get(game.state().ball, .parent).?;
                                if (ball_parent != game.state().ball) {
                                    try game.set(game.state().ball, .parent, game.state().ball);
                                    try physics.set(game.state().ball, .velocity, vec2(game.state().ball_speed, game.state().ball_speed));
                                }
                            },
                            .p => game.state().game_state = .paused,
                            .q => core.schedule(.exit),
                            else => {},
                        }
                    },
                    .game_over => {
                        game.state().game_state = .ready;
                    },
                    .ready => {
                        game.state().game_state = .playing;
                    },
                    .paused => {
                        switch (ev.key) {
                            .p => game.state().game_state = .playing,
                            else => {},
                        }
                    }
                }
            },
            .key_release => |ev| {
                switch (ev.key) {
                    .left => if (velocity.v[0] < 0.0) { velocity.v[0] = 0.0; },
                    .right => if (velocity.v[0] > 0.0) { velocity.v[0] = 0.0; },
                    else => {},
                }
            },
            .close => core.schedule(.exit),
            else => {},
        }
    }

    try physics.set(game.state().player, .velocity, velocity);
}

fn tick_render(game: *Mod,
    core: *mach.Core.Mod,
    sprite: *Sprite.Mod,
    sprite_pipeline: *SpritePipeline.Mod,
    text_pipeline: *gfx.TextPipeline.Mod,
    text: *gfx.Text.Mod) !void {

    const width_px: f32 = game.state().width;
    const height_px: f32 = game.state().height;
    const projection = math.Mat4x4.projection2D(.{
         .left = -width_px / 2.0,
         .right = width_px / 2.0,
         .bottom = -height_px / 2.0,
         .top = height_px / 2.0,
         .near = -0.1,
         .far = 100000,
    });
    const view_projection = projection.mul(&Mat4x4.translate(vec3(0, 0, 0)));
    // TODO: figure out why to setting the projection matrix in a different order impacts render order.
    //       i.e. background comes before bricks if background projection is added after brick projection.
    try sprite_pipeline.set(game.state().background_pipeline, .view_projection, view_projection);
    try sprite_pipeline.set(game.state().pipeline, .view_projection, view_projection);
    try text_pipeline.set(game.state().text_pipeline, .view_projection, view_projection);

    // Render
    // Create a command encoder for this frame
    const label = @tagName(name) ++ ".tick";
    game.state().frame_encoder = core.state().device.createCommandEncoder(&.{ .label = label });

    // Grab the back buffer of the swapchain
    // TODO(Core)
    const back_buffer_view = mach.core.swap_chain.getCurrentTextureView().?;
    defer back_buffer_view.release();

    // Begin render pass
    const color_attachments = [_]gpu.RenderPassColorAttachment{.{
        .view = back_buffer_view,
        .clear_value = gpu.Color{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0 },
        .load_op = .clear,
        .store_op = .store,
    }};
    game.state().frame_render_pass = game.state().frame_encoder.beginRenderPass(&gpu.RenderPassDescriptor.init(.{
        .label = label,
        .color_attachments = &color_attachments,
    }));

    // Sprite render
    sprite.schedule(.update);
    sprite_pipeline.state().render_pass = game.state().frame_render_pass;
    sprite_pipeline.schedule(.pre_render);
    sprite_pipeline.schedule(.render);

    // Update score text
    try utils.updateText(text, game.state().score_text, "Score\n {d:>8}", .{game.state().score});
    try utils.updateText(text, game.state().high_score_text, "High Score\n {d:>8}", .{game.state().high_score});

    // Render text
    text.schedule(.update);
    text_pipeline.state().render_pass = game.state().frame_render_pass;
    text_pipeline.schedule(.pre_render);
    text_pipeline.schedule(.render);

    // Finish the frame once rendering is done.
    game.schedule(.end_frame);
}

fn endFrame(game: *Mod, core: *mach.Core.Mod) !void {
    game.state().frame_count += 1;

    // Finish render pass
    game.state().frame_render_pass.end();
    const label = @tagName(name) ++ ".endFrame";
    var command = game.state().frame_encoder.finish(&.{ .label = label });
    core.state().queue.submit(&[_]*gpu.CommandBuffer{command});
    command.release();
    game.state().frame_encoder.release();
    game.state().frame_render_pass.release();

    core.schedule(.update);
    core.schedule(.present_frame);
}

fn tick_game_logic(game: *Mod,
    physics: *Physics.Mod,
    entities: *mach.Entities.Mod,
    sprite: *Sprite.Mod,
    text: *gfx.Text.Mod,
    audio: *mach.Audio.Mod,
) !void {
    const prev_state = game.state().game_state;

    const width: f32 = game.state().width;
    const height: f32 = game.state().height;

    // Update children transforms
    var children = try entities.query(.{
        .ids = mach.Entities.Mod.read(.id),
        .parents = Mod.read(.parent),
        .transform = gfx.Sprite.Mod.write(.transform),
        .local_transform = Mod.read(.local_transform),
    });
    while (children.next()) |c| {
        for (c.ids, c.parents, c.transform, c.local_transform) |id, parent, *transform, local_transform| {
            if (id != parent) {
                const t = sprite.get(parent, .transform).?;
                transform.* = t.mul(&local_transform);
            }
        }
    }

    // Game logic
    var q_collision = try entities.query(.{
        .ids = mach.Entities.Mod.read(.id),
        .is_contact = Physics.Mod.read(.is_contact),
        .contact_source = Physics.Mod.read(.contact_source),
        .contact_target = Physics.Mod.read(.contact_target),
    });
    while (q_collision.next()) |c| {
        for (c.ids, c.contact_source, c.contact_target) |contact_id, source, target| {
            if (source == game.state().ball and target == game.state().floor) {
                game.state().lives_left -= 1;
                if (game.state().lives_left > 0) {
                    // Move one live off screen
                    const ball = game.state().lives_balls[game.state().lives_left-1];
                    try sprite.set(ball, .transform, Mat4x4.translate(vec3(0.0, -height/2.0 - 20, 0.0)));
                } else {
                    // game over
                    game.state().lives_left = 3;
                    if (game.state().high_score < game.state().score) {
                        game.state().high_score = game.state().score;
                    }
                    game.state().score = 0;
                    // reset lives
                    var x_pos: f32 = -width / 2.0 + 20;
                    for (game.state().lives_balls) |ball| {
                        try sprite.set(ball, .transform, Mat4x4.translate(vec3(x_pos, -height/2.0+10.0, 0.0)));
                        x_pos += 20.0;
                    }

                    game.state().game_state = .game_over;
                }
                
                try game.set(source, .parent, game.state().player);
                try physics.set(source, .velocity, vec2(0.0, 0.0));

            } else if (source == game.state().ball) {
                const is_hittable = game.get(target, .is_hittable);
                if (is_hittable) |_| {
                    const reward = game.get(target, .reward).?;
                    game.state().score += reward;
                    game.state().bricks_left -= 1;
                    try entities.remove(target);

                    if (game.state().bricks_left == 0) {
                        // new level
                        game.state().paddle_speed += 50;
                        game.state().ball_speed += 50;

                        // schedule reset level

                        try buildLevel(&game.state().spritesheet, game.state().pipeline, entities, sprite, game, physics);
                        try game.set(source, .parent, game.state().player);
                        try physics.set(source, .velocity, vec2(0.0, 0.0));
                        // Move ball so it does not hit bricks in new level
                        try sprite.set(source, .transform, Mat4x4.translate(vec3(0.0, -height/2.0+50.0, 0.0)));
                    }
                }
            }
            try entities.remove(contact_id);

            const impact_entity = try entities.new();
            try audio.set(impact_entity, .samples, game.state().impact_sfx.samples);
            try audio.set(impact_entity, .channels, game.state().impact_sfx.channels);
            try audio.set(impact_entity, .playing, true);
            try audio.set(impact_entity, .index, 0);
        }
    }

    if (prev_state == .game_over and game.state().game_state == .ready) {
        try buildLevel(&game.state().spritesheet, game.state().pipeline, entities, sprite, game, physics);
    }

    // Update info text
    switch (game.state().game_state) {
        .ready => {
            try utils.updateText(text, game.state().info_text, "Press any key to start", .{});
        },
        .playing => {
            try utils.updateText(text, game.state().info_text, " ", .{});
        },
        .game_over => {
            try utils.updateText(text, game.state().info_text, "            Game over!", .{});
        },
        .paused => {
            try utils.updateText(text, game.state().info_text, "            Paused", .{});
        }
    }    
}

fn tick(
    game: *Mod,
    physics: *Physics.Mod,
) !void {
    const delta_time = game.state().timer.lap();    
    game.state().time += delta_time;

    game.schedule(.inputs);
    if (game.state().game_state == .playing) {
        physics.scheduleWithArgs(.tick, .{delta_time});
    }
    game.schedule(.game_logic);
    game.schedule(.render);
}

fn audioStateChange(
    entities: *mach.Entities.Mod,
    audio: *mach.Audio.Mod,
    app: *Mod,
) !void {
    // Find audio entities that are no longer playing
    var q = try entities.query(.{
        .ids = mach.Entities.Mod.read(.id),
        .playings = mach.Audio.Mod.read(.playing),
    });

    while (q.next()) |v| {
        for (v.ids, v.playings) |id, playing| {
            if (playing) continue;

            if (app.get(id, .is_bgm)) |_| {
                // Repeat background music
                try audio.set(id, .index, 0);
                try audio.set(id, .playing, true);
            } else {
                // Remove the entity for the old sound
                try entities.remove(id);
            }
        }
    }
}
