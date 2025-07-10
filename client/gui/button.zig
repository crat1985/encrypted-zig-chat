const C = @import("c.zig").C;
const Font = @import("font.zig");
const txt_mod = @import("txt.zig");
const GUI = @import("../gui.zig");

pub const ButtonColors = struct {
    basic: C.Color = C.BLUE,
    hover: C.Color = C.DARKBLUE,
    pressed: C.Color = C.PURPLE,
    disabled: C.Color = C.GRAY,
    font_color: C.Color = C.WHITE,
};

pub const ButtonPadding = struct {
    left: f32 = 6,
    top: f32 = 3,
    right: f32 = 6,
    bottom: f32 = 3,
};

pub fn Button(comptime T: type) type {
    return struct {
        real_bounds: C.Rectangle,
        txt_bounds: C.Rectangle,
        bg: C.Color,
        fg: C.Color,
        font_size: c_int,
        txt: ?[]const T,

        const Self = @This();

        fn get_bounds_with_padding(root_bounds: C.Rectangle, padding: ButtonPadding) C.Rectangle {
            return C.Rectangle{
                .x = root_bounds.x + padding.left,
                .y = root_bounds.y + padding.top,
                .width = root_bounds.width - padding.left - padding.right,
                .height = root_bounds.height - padding.top - padding.bottom,
            };
        }

        pub fn init_default_center(bounds: C.Rectangle, is_enabled: bool) Self {
            return Self.init_default_text_button_center(bounds, null, is_enabled);
        }

        pub fn init_default_text_button_center(bounds: C.Rectangle, txt: ?[]const T, is_enabled: bool) Self {
            return Self.init(bounds, txt, ButtonPadding{}, ButtonColors{}, .Center, .Center, GUI.FONT_SIZE, is_enabled);
        }

        pub fn init_default_text_button(bounds: C.Rectangle, txt: []const T, h_align: txt_mod.Alignment, v_align: txt_mod.Alignment, is_enabled: bool) Self {
            return Self.init(bounds, txt, ButtonPadding{}, ButtonColors{}, h_align, v_align, GUI.FONT_SIZE, is_enabled);
        }

        pub fn init(bounds: C.Rectangle, txt: ?[]const T, padding: ?ButtonPadding, colors: ?ButtonColors, h_align: txt_mod.Alignment, v_align: txt_mod.Alignment, maxFontSize: c_int, is_enabled: bool) Self {
            const padding_unwrap = padding orelse ButtonPadding{};

            var font_size: c_int = GUI.FONT_SIZE;

            const real_bounds = if (txt) |txt_unwrap| blk: {
                const max_txt_bounds = Self.get_bounds_with_padding(bounds, padding_unwrap);

                font_size = txt_mod.GetFontSize(T, txt_unwrap, max_txt_bounds, maxFontSize);
                const txt_size = txt_mod.getTextSize(T, txt_unwrap, max_txt_bounds, font_size);

                const start_x = switch (h_align) {
                    .Center => bounds.x + bounds.width / 2 - txt_size.x / 2 - padding_unwrap.left,
                    .Start => bounds.x,
                    .End => bounds.x + bounds.width - txt_size.x - padding_unwrap.left - padding_unwrap.right,
                };

                const start_y = switch (v_align) {
                    .Center => bounds.y + bounds.height / 2 - txt_size.y / 2 - padding_unwrap.top,
                    .Start => bounds.y,
                    .End => bounds.y + bounds.height - txt_size.y - padding_unwrap.top - padding_unwrap.bottom,
                };

                break :blk C.Rectangle{
                    .x = start_x,
                    .y = start_y,
                    .width = txt_size.x + padding_unwrap.left + padding_unwrap.right,
                    .height = txt_size.y + padding_unwrap.top + padding_unwrap.bottom,
                };
            } else bounds;

            const txt_bounds = Self.get_bounds_with_padding(real_bounds, padding_unwrap);

            const colors_unwrap = colors orelse ButtonColors{};

            var self = Self{
                .real_bounds = real_bounds,
                .txt_bounds = txt_bounds,
                .bg = colors_unwrap.basic,
                .fg = colors_unwrap.font_color,
                .font_size = font_size,
                .txt = txt,
            };

            if (!is_enabled) {
                self.bg = colors_unwrap.disabled;
            } else if (self.is_hover()) {
                self.bg = colors_unwrap.hover;

                if (C.IsMouseButtonDown(C.MOUSE_BUTTON_LEFT)) {
                    self.bg = colors_unwrap.pressed;
                }
            }

            return self;
        }

        pub fn is_hover(self: Self) bool {
            return C.CheckCollisionPointRec(C.GetMousePosition(), self.real_bounds);
        }

        pub fn is_clicked(self: Self) bool {
            if (self.is_hover()) {
                if (C.IsMouseButtonPressed(C.MOUSE_BUTTON_LEFT)) {
                    return true;
                }
            }

            return false;
        }

        pub fn set_cursor(self: Self, cursor: *c_int) void {
            if (self.is_hover()) {
                cursor.* = C.MOUSE_CURSOR_POINTING_HAND;
            }
        }

        pub fn draw(self: Self) void {
            C.DrawRectangleRec(self.real_bounds, self.bg);
            if (self.txt) |txt| {
                txt_mod.drawText(T, txt, self.txt_bounds, GUI.FONT_SIZE, self.fg, .Center, .Center);
            }
        }
    };
}
