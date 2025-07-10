const C = @import("../c.zig").C;
const Padding = @import("padding.zig");
const Alignment2 = @import("alignment.zig").Alignment2;

pub const ParentRect = struct {
    bounds: C.Rectangle,
    child_bounds: C.Rectangle,
    color: C.Color,

    const Self = @This();

    pub fn init(bounds: C.Rectangle, child_size: C.Vector2, padding: ?Padding, alignment: Alignment2, color: C.Color) Self {
        const padding_unwrap = padding orelse Padding{};

        const child_bounds: C.Rectangle = alignment.get_subbounds(bounds, child_size);

        const real_bounds = padding_unwrap.add_padding(child_bounds);

        return Self{
            .bounds = real_bounds,
            .child_bounds = child_bounds,
            .color = color,
        };
    }

    pub fn draw(self: Self) C.Rectangle {
        C.DrawRectangleRec(self.bounds, self.color);

        return self.child_bounds;
    }

    pub fn is_hover(self: Self) bool {
        return C.CheckCollisionPointRec(C.GetMousePosition(), self.bounds);
    }

    pub fn is_clicked(self: Self) bool {
        if (self.is_hover()) {
            if (C.IsMouseButtonPressed(C.MOUSE_BUTTON_LEFT)) {
                return true;
            }
        }

        return false;
    }
};
