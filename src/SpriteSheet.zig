const std = @import("std");
const ArrayList = std.array_list.ArrayList;

pub const Sprite = struct {
    name: []u8,
    source: []i32,
    origin: []i32,
};

pub const Sheet = struct {
    sprites: []Sprite,
    animations: std.json.Value,
};

pub const SheetMap = std.StringHashMap(Sprite);

pub const SpriteSheet = struct {
    allocator: std.mem.Allocator,
    sprites: SheetMap,

    pub fn init(allocator: std.mem.Allocator) SpriteSheet {
        return SpriteSheet{
            .allocator = allocator,
            .sprites = SheetMap.init(allocator),
        };
    }

    pub fn get(self: *SpriteSheet, name: [] const u8) ?Sprite {
        const sprite = self.sprites.get(name);
        return sprite;
    }

    pub fn put(self: *SpriteSheet, sprite: Sprite) !void {
        const allocator = self.allocator;
        try self.sprites.put(try allocator.dupe(u8, sprite.name), 
            .{
                .name = try allocator.dupe(u8, sprite.name),
                .source = try allocator.dupe(i32, sprite.source),
                .origin = try allocator.dupe(i32, sprite.origin)
            }
        );
    }

    pub fn deinit(self: *SpriteSheet) void {
        const allocator = self.allocator;
        const sprites = self.sprites;

        var it = sprites.iterator();
        while (it.next()) |kv| {
            allocator.free(kv.key_ptr.*);
            allocator.free(kv.value_ptr.*.name);
            allocator.free(kv.value_ptr.*.source);
            allocator.free(kv.value_ptr.*.origin);
        }
        self.sprites.deinit();
    }
};

pub fn loadPixiSpriteAtlas(allocator: std.mem.Allocator, filename: [] const u8, sheet_map: *SpriteSheet) !void {
    const file = try std.fs.cwd().openFile(filename, .{.mode = .read_only});
    defer file.close();

    var buffered = std.io.bufferedReader(file.reader());
    var reader = buffered.reader();    
    const data = try reader.readAllAlloc(allocator, 4*1024*1024);
    defer allocator.free(data);

    const atlas = try std.json.parseFromSlice(Sheet, allocator, data, .{});
    defer atlas.deinit();

    for (atlas.value.sprites) |sprite| {
        std.debug.print("Add {s} \n", .{sprite.name});
        try sheet_map.put(sprite);
        std.debug.print("Contain {s} {} \n", .{sprite.name, sheet_map.sprites.contains(sprite.name)});
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print(
            "error: missing filename\n Usage: sheet <filename>\n", .{});
        return ;
    }
    const filename = args[1];
    std.debug.print("Open file: {s}\n", .{filename});

    var sheet_map = SpriteSheet.init(allocator);
    try loadPixiSpriteAtlas(allocator, filename, &sheet_map);
    defer sheet_map.deinit();

    const s = sheet_map.get("core_0_Layer 0").?;
    std.debug.print("Lookup {d} {}\n", .{s.source, sheet_map.sprites.count()});

    var it = sheet_map.sprites.keyIterator();
    while (it.next()) |key| {
        std.debug.print("{s}\n", .{key.*});
    }
}
