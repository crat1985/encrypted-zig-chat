const C = @import("c.zig");

pub const Alignment = enum(u8) {
    Center,
    Start,
    End,
};

pub const Alignment2 = struct {
    x: Alignment,
    y: Alignment,

    const Self = @This();

    pub const Center: Self = .{ .x = .Center, .y = .Center };

    pub fn get_subbounds(self: Self, bounds: C.Rectangle, size: C.Vector2) C.Rectangle {
        const startx = switch (self.x) {
            .Center => bounds.x + bounds.width / 2 - size.x / 2,
            .Start => bounds.x,
            .End => bounds.x + bounds.width - size.x,
        };

        const starty = switch (self.y) {
            .Center => bounds.y + bounds.height / 2 - size.y / 2,
            .Start => bounds.y,
            .End => bounds.x + bounds.height - size.y,
        };

        return C.Rectangle{
            .x = startx,
            .y = starty,
            .width = size.x,
            .height = size.y,
        };
    }
};
