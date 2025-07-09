const C = @import("c.zig").C;
const Font = @import("font.zig");

pub const ButtonColors = struct {
    basic: C.Color = C.BLUE,
    hower: C.Color = C.DARKBLUE,
    pressed: C.Color = C.PURPLE,
    disabled: C.Color = C.GRAY,
    font_color: C.Color = C.WHITE,
};

pub const ButtonPadding = struct {
    left: f32 = 3,
    top: f32 = 3,
    right: f32 = 3,
    bottom: f32 = 3,
};

pub const Button = struct {
    real_bounds: C.Rectangle,
    padding: ButtonPadding,
    colors: ButtonColors,
    txt: ?Font.SliceKind,

    pub fn init(bounds: C.Rectangle, txt: ?Font.SliceKind, padding: ?ButtonPadding, colors: ?ButtonColors) void {}
};

///Returns if the button is pressed
pub fn draw_text_button(bounds: C.Rectangle, colors: ?ButtonColors, txt: Font.SliceKind) bool {}
