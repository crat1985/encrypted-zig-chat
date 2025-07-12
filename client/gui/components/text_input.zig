const C = @import("../c.zig").C;
const ParentRect = @import("parent_rect.zig").ParentRect;
const txt_mod = @import("../txt.zig");
const GUI = @import("../../gui.zig");
const Padding = @import("padding.zig");
const Alignment2 = @import("alignment.zig").Alignment2;

pub fn TextInput(comptime T: type) type {
    return struct {
        rect: ParentRect,
        txt: []const T,
        txt_color: C.Color,
        font_size: c_int,

        const Self = @This();

        pub fn initFull(txt: []const T, root_bounds: C.Rectangle, padding: Padding, alignment: Alignment2, bg: C.Color, fg: C.Color, max_font_size: *c_int) Self {
            const rect = ParentRect.init_text(T, txt, root_bounds, padding, alignment, bg, max_font_size);

            return Self{
                .rect = rect,
                .txt = txt,
                .txt_color = fg,
                .font_size = max_font_size.*,
            };
        }

        pub fn initRect(txt: []const T, rect: ParentRect, txt_color: C.Color, font_size: c_int) Self {
            return Self{
                .txt = txt,
                .rect = rect,
                .txt_color = txt_color,
                .font_size = font_size,
            };
        }

        pub fn draw(self: Self) void {
            const txt_bounds = self.rect.draw();

            txt_mod.drawText(T, self.txt, txt_bounds, self.max_font_size, self.txt_color, .{ .x = .Center, .y = .Center });
        }
    };
}
