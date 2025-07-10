// const C = @import("c.zig").C;
// const GUI = @import("../gui.zig");
// const std = @import("std");
// const Font = @import("font.zig");
// const txt_mod = @import("txt.zig");
// const Padding = @import("padding.zig");

// const Alignment = txt_mod.Alignment;

// const allocator = std.heap.page_allocator;

// pub fn TextInput(comptime T: type) type {
//     return struct {
//         bounds: C.Rectangle,
//         txt_bounds: C.Rectangle,
//         text_align: txt_mod.Alignment2,
//         font_size: c_int,
//         txt: []const T,
//         // cursor_pos: usize,
//         bg: C.Color,
//         fg: C.Color,

//         const Self = @This();

//         pub fn init(txt: []const T, bounds: C.Rectangle, max_font_size: c_int, alignment: txt_mod.Alignment2, text_align: txt_mod.Alignment2, padding: ?Padding, bg: C.Color, fg: C.Color, max_size: ?usize) Self {
//             const padding_unwrap = padding orelse Padding{};

//             const max_txt_bounds = padding_unwrap.get_sub_bound(bounds);

//             const font_size = txt_mod.GetFontSize(T, txt.*, max_txt_bounds, max_font_size);
//             const txt_size = txt_mod.getTextSize(T, txt.*, max_txt_bounds, font_size);

//             const txt_bounds = alignment.get_subbounds(max_txt_bounds, txt_size);

//             const real_bounds = padding_unwrap.add_padding(txt_bounds);

//             return Self{
//                 .bounds = real_bounds,
//                 .txt_bounds = txt_bounds,
//                 .text_align = text_align,
//                 .font_size = font_size,
//                 .txt = txt,
//                 .bg = bg,
//                 .fg = fg,
//                 .max_size = max_size,
//             };
//         }

//         pub fn draw(self: Self) void {
//             C.DrawRectangleRec(self.bounds, self.bg);
//             txt_mod.drawText(T, self.txt.*, self.txt_bounds, self.font_size, self.fg, self.text_align);
//         }

//         pub fn get_char() ?T {
//             const c: u21 = @intCast(C.GetCharPressed());
//             if (c == 0) return null;

//             switch (T) {
//                 u8 => switch (c) {
//                     //Handle ASCII chars
//                     0...127 => return @intCast(c),
//                     else => {
//                         std.log.err("Unsupported character {u}", .{c});
//                         return null;
//                     },
//                 },
//                 c_int => return c,
//                 else => @compileError("Unsupported type " ++ @typeName(T)),
//             }
//         }

//         pub fn is_backspace_pressed() bool {
//             return C.IsKeyPressed(C.KEY_BACKSPACE) or C.IsKeyPressedRepeat(C.KEY_BACKSPACE);
//         }

//         pub fn append_to_slice(slice: *[]T, element: T) !void {
//             slice.* = try allocator.realloc(slice.*, slice.len + 1);
//             slice.*[slice.len - 1] = element;
//         }
//     };
// }
