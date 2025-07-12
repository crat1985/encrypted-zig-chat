const C = @import("../c.zig").C;
const Font = @import("../font.zig");
const txt_mod = @import("../txt.zig");
const GUI = @import("../../gui.zig");
const Padding = @import("padding.zig");
const Alignment2 = @import("alignment.zig").Alignment2;
const ParentRect = @import("parent_rect.zig").ParentRect;

pub const ButtonColors = struct {
    basic: C.Color = C.BLUE,
    hover: C.Color = C.DARKBLUE,
    pressed: C.Color = C.PURPLE,
    disabled: C.Color = C.GRAY,
    font_color: C.Color = C.WHITE,
};

pub const Button = struct {
    rect: ParentRect,

    const Self = @This();

    pub fn init(rect: ParentRect, colors: ButtonColors, is_enabled: bool) Self {
        var self = Self{
            .rect = rect,
        };

        if (!is_enabled) {
            self.rect.color = colors.disabled;
        } else if (self.is_hover()) {
            self.rect.color = colors.hover;

            if (C.IsMouseButtonDown(C.MOUSE_BUTTON_LEFT)) {
                self.rect.color = colors.pressed;
            }
        }

        return self;
    }

    pub fn is_hover(self: Self) bool {
        return self.rect.is_hover();
    }

    pub fn is_clicked(self: Self) bool {
        return self.rect.is_clicked();
    }

    pub fn set_cursor(self: Self, cursor: *c_int) void {
        if (self.is_hover()) {
            cursor.* = C.MOUSE_CURSOR_POINTING_HAND;
        }
    }

    pub fn draw(self: Self) C.Rectangle {
        return self.rect.draw();
    }
};
