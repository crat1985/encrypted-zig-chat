const C = @import("c.zig").C;
const std = @import("std");
const GUI = @import("../gui.zig");
const Font = @import("font.zig");
const Alignment2 = @import("alignment.zig").Alignment2;

fn isFontSizeFitting(comptime T: type, txt: []const T, bounds: C.Rectangle, fontSize: c_int) bool {
    var txt_mut = txt;

    var y_offset: f32 = 0;

    while (txt_mut.len > 0) {
        var n: usize = undefined;
        _ = measureLine(T, txt_mut, bounds, fontSize, &n);

        txt_mut = txt_mut[n..];

        y_offset += 1;

        if (y_offset > bounds.height) return false;
    }

    return true;
}

fn measureLine(comptime T: type, txt: []const T, bounds: C.Rectangle, fontSize: c_int, number_read: *usize) c_int {
    var x_offset: c_int = 0;
    var read: usize = 0;

    for (txt) |codepoint| {
        switch (codepoint) {
            '\r' => {
                if (read + 1 < txt.len) {
                    if (txt[read + 1] == '\n') {
                        continue;
                    }
                }
                number_read.* = read;
                return x_offset;
            },
            '\n' => {
                number_read.* = read;
                return x_offset;
            },
            else => {},
        }

        const font = Font.getCharFont(codepoint, fontSize);
        const glyph = C.GetGlyphInfo(font, codepoint);

        if (x_offset + glyph.advanceX + Font.SPACING > @as(c_int, @intFromFloat(bounds.width))) {
            number_read.* = read;
            return x_offset;
        }

        x_offset += glyph.advanceX + Font.SPACING;

        read += 1;
    }

    number_read.* = read;

    return x_offset;
}

fn getLineCount(comptime T: type, txt: []const T, bounds: C.Rectangle, fontSize: c_int) usize {
    var txt_mut = txt;
    var line_count: usize = 0;

    while (txt_mut.len > 0) : (line_count += 1) {
        var line_char_count: usize = undefined;
        _ = measureLine(T, txt_mut, bounds, fontSize, &line_char_count);

        txt_mut = txt_mut[line_char_count..];
    }

    return line_count;
}

pub fn getTextSize(comptime T: type, txt: []const T, bounds: C.Rectangle, fontSize: c_int) C.Vector2 {
    var txt_mut = txt;
    var line_count: f32 = 0;

    var max_width: c_int = 0;

    while (txt_mut.len > 0) : (line_count += 1) {
        var line_char_count: usize = undefined;
        const line_width = measureLine(T, txt_mut, bounds, fontSize, &line_char_count);

        if (line_width > max_width) max_width = line_width;

        txt_mut = txt_mut[line_char_count..];
    }

    const size = C.Vector2{
        .x = @floatFromInt(max_width),
        .y = line_count * @as(f32, @floatFromInt(fontSize)) * 1.5,
    };

    return size;
}

pub fn GetFontSize(comptime T: type, txt: []const T, bounds: C.Rectangle, maxFontSize: c_int) c_int {
    var fontSize = maxFontSize;

    while (!isFontSizeFitting(T, txt, bounds, fontSize)) {
        fontSize -= 1;
    }

    return fontSize;
}

pub fn drawText(comptime T: type, txt: []const T, bounds: C.Rectangle, maxFontSize: c_int, tint: C.Color, text_align: Alignment2) void {
    const font_size = GetFontSize(T, txt, bounds, maxFontSize);
    const font_size_f32: f32 = @floatFromInt(font_size);

    const line_count = getLineCount(T, txt, bounds, font_size);
    const txt_height = @as(f32, @floatFromInt(line_count)) * font_size_f32 * 1.5;

    const y_top = switch (text_align.y) {
        .Center => bounds.y + bounds.height / 2 - txt_height / 2,
        .Start => bounds.y,
        .End => bounds.y + bounds.height - txt_height,
    };

    var txt_mut = txt;
    var i: usize = 0;

    while (txt_mut.len > 0) : (i += 1) {
        var line_char_count: usize = undefined;
        const txt_width: f32 = @floatFromInt(measureLine(T, txt_mut, bounds, font_size, &line_char_count));

        const line = txt_mut[0..line_char_count];

        txt_mut = txt_mut[line_char_count..];

        const x_left = switch (text_align.x) {
            .Center => bounds.x + bounds.width / 2 - txt_width / 2,
            .Start => bounds.x,
            .End => bounds.x + bounds.width - txt_width,
        };

        var x_offset: f32 = x_left;

        for (line) |codepoint| {
            switch (codepoint) {
                '\r', '\n' => break,
                else => {},
            }
            const font = Font.getCharFont(codepoint, font_size);
            const glyph = C.GetGlyphInfo(font, codepoint);
            C.DrawTextCodepoint(font, codepoint, .{ .x = x_offset, .y = y_top + @as(f32, @floatFromInt(i)) * font_size_f32 * 1.5 }, font_size_f32, tint);
            x_offset += @floatFromInt(glyph.advanceX + Font.SPACING);
        }
    }
}
