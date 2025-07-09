const C = @import("c.zig").C;
const std = @import("std");
const GUI = @import("../gui.zig");
const Font = @import("font.zig");

pub const Alignment = enum(u8) {
    Center,
    Start,
    End,
};

// pub fn measureSliceBounds(kind: SliceKind, maxFontSize: c_int, bounds: C.Rectangle) C.Vector2 {
//     const font_size = getSliceFontSize(kind, maxFontSize, bounds);
//     return measureSlice(kind, font_size);
// }

// ///Returns the font size
// pub fn getSliceFontSize(kind: SliceKind, maxFontSize: c_int, bounds: C.Rectangle) c_int {
//     var font_size: f32 = @floatFromInt(maxFontSize);

//     while (true) {
//         const txt_size = measureSlice(kind, @intFromFloat(font_size));
//         if (txt_size.x <= bounds.width and txt_size.y <= bounds.height) break;
//         font_size = (font_size * 4) / 5;
//     }

//     return @intFromFloat(font_size);
// }

// pub fn measureText(txt: []const u8, fontSize: c_int) C.Vector2 {
//     return measureSlice(.{ .Bytes = txt }, fontSize);
// }

// pub fn measureCodepoints(txt: []const c_int, fontSize: c_int) C.Vector2 {
//     return measureSlice(.{ .Codepoints = txt }, fontSize);
// }

// pub fn drawText(txt: []const u8, bounds: C.Rectangle, maxFontSize: c_int, tint: C.Color, h_align: Alignment, v_align: Alignment) void {
//     return drawSlice(.{ .Bytes = txt }, bounds, maxFontSize, tint, h_align, v_align);
// }

// pub fn drawCodepoints(txt: []const c_int, bounds: C.Rectangle, maxFontSize: c_int, tint: C.Color, h_align: Alignment, v_align: Alignment) void {
//     return drawSlice(.{ .Codepoints = txt }, bounds, maxFontSize, tint, h_align, v_align);
// }

// pub const SliceKind = union(enum(u8)) {
//     Bytes: []const u8,
//     Codepoints: []const c_int,
// };

// fn measureSlice(comptime T: type, txt: []const T, fontSize: c_int) C.Vector2 {
//     var max_width: f32 = 0;
//     var y: f32 = fontSize;

//     var total_width: f32 = 0;

//     for (txt) |codepoint| {
//         switch (codepoint) {
//             '\r' => {
//                 if (total_width > max_width) max_width = total_width;
//                 total_width = 0;
//                 continue;
//             },
//             '\n' => {
//                 if (total_width > max_width) max_width = total_width;
//                 total_width = 0;
//                 y += @divTrunc(fontSize * 5, 4);
//                 continue;
//             },
//             else => {},
//         }
//         const font = Font.getCharFont(codepoint, fontSize);
//         const glyph = C.GetGlyphInfo(font, codepoint);
//         total_width += glyph.advanceX + Font.SPACING;
//     }

//     if (total_width > max_width) max_width = total_width;

//     return C.Vector2{
//         .x = max_width,
//         .y = @floatFromInt(y),
//     };
// }

fn isFontSizeFitting(comptime T: type, txt: []const T, bounds: C.Rectangle, fontSize: c_int) bool {
    var txt_mut = txt;

    var y_offset: f32 = 0;

    while (txt_mut.len > 0) {
        var n: usize = undefined;
        _ = measureLine(T, txt, bounds, fontSize, &n);

        txt_mut = txt_mut[n..];

        y_offset += 1;

        if (y_offset > bounds.height) return false;
    }

    return true;
}

fn measureLine(comptime T: type, txt: []const T, bounds: C.Rectangle, fontSize: c_int, number_read: *usize) c_int {
    var x_offset: c_int = 0;

    for (txt, 0..) |codepoint, i| {
        switch (codepoint) {
            '\r' => {
                if (i + 1 < txt.len) {
                    if (txt[i + 1] == '\n') {
                        continue;
                    }
                }
                number_read.* = i + 1;
                return x_offset;
            },
            '\n' => {
                number_read.* = i + 1;
                return x_offset;
            },
            else => {},
        }

        const font = Font.getCharFont(codepoint, fontSize);
        const glyph = C.GetGlyphInfo(font, codepoint);

        if (x_offset + glyph.advanceX + Font.SPACING > bounds.width) {
            number_read.* = i;
            return x_offset;
        }

        x_offset += glyph.advanceX + Font.SPACING;
    }

    return x_offset;
}

pub fn GetFontSize(comptime T: type, txt: []const T, bounds: C.Rectangle, maxFontSize: c_int) c_int {
    var fontSize = maxFontSize;

    while (!isFontSizeFitting(T, txt, bounds, fontSize)) {
        fontSize -= 1;
    }

    return fontSize;
}

fn drawText(comptime T: type, txt: []const T, bounds: C.Rectangle, maxFontSize: c_int, tint: C.Color, h_align: Alignment, v_align: Alignment) void {
    const font_size = GetFontSize(T, txt, bounds, maxFontSize);

    const x_left = switch (h_align) {
        .Center => bounds.x + bounds.width / 2 - txt_size.x / 2,
        .Start => bounds.x,
        .End => bounds.x + bounds.width - txt_size.x,
    };

    const y_top = switch (v_align) {
        .Center => bounds.y + bounds.height / 2 - txt_size.y / 2,
        .Start => bounds.y,
        .End => bounds.y + bounds.height - txt_size.y,
    };

    var x_offset = x_left;
    var y_offset = y_top;

    switch (kind) {
        inline else => |txt| for (txt) |codepoint| {
            switch (codepoint) {
                '\r' => {
                    x_offset = x_left;
                    continue;
                },
                '\n' => {
                    x_offset = x_left;
                    y_offset += @as(f32, @floatFromInt(font_size)) * 5 / 4;
                    continue;
                },
                else => {},
            }
            const font = Font.getCharFont(codepoint, font_size);
            const glyph = C.GetGlyphInfo(font, codepoint);
            C.DrawTextCodepoint(font, codepoint, .{ .x = x_offset, .y = y_offset }, @floatFromInt(font_size), tint);
            x_offset += @floatFromInt(glyph.advanceX + Font.SPACING);
        },
    }
}

pub fn drawDefaultButtonTextRect(bounds: C.Rectangle, fontColor: C.Color, bgColor: C.Color, kind: SliceKind) void {
    drawTextRect(bounds, GUI.button_padding, GUI.button_padding, fontColor, GUI.FONT_SIZE, bgColor, kind, .Center, .Center);
}

pub fn getRealTextRect(bounds: C.Rectangle, h_padding: c_int, v_padding: c_int, maxFontSize: c_int, kind: SliceKind, h_align: Alignment, v_align: Alignment) C.Rectangle {
    const txt_bounds = C.Rectangle{
        .x = bounds.x + @as(f32, @floatFromInt(h_padding)),
        .y = bounds.y + @as(f32, @floatFromInt(v_padding)),
        .width = bounds.width - @as(f32, @floatFromInt(h_padding * 2)),
        .height = bounds.height - @as(f32, @floatFromInt(v_padding * 2)),
    };

    const fontSize = getSliceFontSize(kind, maxFontSize, txt_bounds);
    const txt_size = measureSlice(kind, fontSize);

    const real_rect = C.Rectangle{
        .x = switch (h_align) {
            .Center => bounds.x + bounds.width / 2 - txt_size.x / 2 - GUI.button_padding,
            .Start => bounds.x,
            .End => bounds.x + bounds.width - txt_size.x - GUI.button_padding * 2,
        },
        .y = switch (v_align) {
            .Center => bounds.y + bounds.height / 2 - txt_size.y / 2 - GUI.button_padding,
            .Start => bounds.y,
            .End => bounds.y + bounds.height - txt_size.y - GUI.button_padding * 2,
        },
        .width = txt_size.x + GUI.button_padding * 2,
        .height = txt_size.y + GUI.button_padding * 2,
    };

    return real_rect;
}

pub fn drawTextRect(bounds: C.Rectangle, h_padding: c_int, v_padding: c_int, fontColor: C.Color, maxFontSize: c_int, bgColor: C.Color, kind: SliceKind, h_align: Alignment, v_align: Alignment) void {
    const real_rect = getRealTextRect(bounds, h_padding, v_padding, maxFontSize, kind, h_align, v_align);

    C.DrawRectangleRec(real_rect, bgColor);

    drawSlice(kind, real_rect, maxFontSize, fontColor, h_align, v_align);
}
