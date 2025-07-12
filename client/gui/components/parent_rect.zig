const C = @import("../c.zig").C;
const Padding = @import("padding.zig");
const Alignment2 = @import("alignment.zig").Alignment2;
const txt_mod = @import("../txt.zig");

pub const ParentRect = struct {
    bounds: C.Rectangle,
    child_bounds: C.Rectangle,
    color: C.Color,

    const Self = @This();

    ///Sets `max_font_size` to the calculated font size
    pub fn init_text(comptime T: type, txt: []const T, bounds: C.Rectangle, padding: Padding, alignment: Alignment2, bg: C.Color, max_font_size: *c_int) Self {
        const txt_max_bounds = padding.get_sub_bound(bounds);

        max_font_size.* = txt_mod.GetFontSize(T, txt, txt_max_bounds, max_font_size);

        const txt_size = txt_mod.getTextSize(T, txt, txt_max_bounds, max_font_size.*);

        return Self.init(bounds, txt_size, padding, alignment, bg);
    }

    pub fn init(bounds: C.Rectangle, child_size: C.Vector2, padding: Padding, alignment: Alignment2, color: C.Color) Self {
        const child_bounds: C.Rectangle = alignment.get_subbounds(bounds, child_size);

        const real_bounds = padding.add_padding(child_bounds);

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
