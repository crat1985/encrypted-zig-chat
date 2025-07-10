left: f32 = 6,
top: f32 = 3,
right: f32 = 6,
bottom: f32 = 3,

const C = @import("c.zig").C;

const Self = @This();

pub fn get_sub_bound(self: Self, root_bounds: C.Rectangle) C.Rectangle {
    return C.Rectangle{
        .x = root_bounds.x + self.left,
        .y = root_bounds.y + self.top,
        .width = root_bounds.width - self.left - self.right,
        .height = root_bounds.height - self.top - self.bottom,
    };
}

pub fn add_padding(self: Self, bounds: C.Rectangle) C.Rectangle {
    return C.Rectangle{
        .x = bounds.x - self.left,
        .y = bounds.y - self.top,
        .width = bounds.width + self.left + self.right,
        .height = bounds.height + self.top + self.bottom,
    };
}
