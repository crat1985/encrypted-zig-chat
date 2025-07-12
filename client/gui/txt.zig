const C = @import("c.zig").C;
const std = @import("std");
const GUI = @import("../gui.zig");
const Font = @import("font.zig");
const Alignment2 = @import("components/alignment.zig").Alignment2;

pub fn Text(comptime T: type) type {
    return struct {
        real_bounds: C.Rectangle,
        txt: []const T,
        font_size: c_int,
        txt_align: Alignment2,

        const Self = @This();

        pub fn init(txt: []const T, bounds: C.Rectangle, max_font_size: c_int, alignment: Alignment2) Self {
            const font_size = Self.GetFontSize(txt, bounds, max_font_size);

            const txt_size = Self.getTextSize(txt, bounds, font_size);

            const real_bounds = alignment.get_subbounds(bounds, txt_size);

            return Self{
                .real_bounds = real_bounds,
                .txt = txt,
                .font_size = font_size,
                .txt_align = alignment,
            };
        }

        fn measureLine(txt: []const T, bounds: C.Rectangle, fontSize: c_int, number_read: *usize) c_int {
            var x_offset: c_int = 0;
            var read: usize = 0;

            for (txt) |codepoint| {
                defer read += 1;

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
            }

            number_read.* = read;

            return x_offset;
        }

        fn getLineCount(txt: []const T, bounds: C.Rectangle, fontSize: c_int) usize {
            var txt_mut = txt;
            var line_count: usize = 0;

            while (txt_mut.len > 0) : (line_count += 1) {
                var line_char_count: usize = undefined;
                _ = measureLine(T, txt_mut, bounds, fontSize, &line_char_count);

                txt_mut = txt_mut[line_char_count..];
            }

            return line_count;
        }

        fn getTextSize(txt: []const T, bounds: C.Rectangle, fontSize: c_int) C.Vector2 {
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

        // pub fn getTextSizeUsingMaxFontSize(txt: []const T, bounds: C.Rectangle, max_font_size: c_int) C.Vector2 {
        //     const font_size = GetFontSize(T, txt, bounds, max_font_size);

        //     return getTextSize(T, txt, bounds, font_size);
        // }

        fn GetFontSize(txt: []const T, bounds: C.Rectangle, maxFontSize: c_int) c_int {
            var fontSize = maxFontSize;

            while (!isFontSizeFitting(T, txt, bounds, fontSize)) {
                fontSize -= 1;
            }

            return fontSize;
        }

        pub fn draw(self: Self, color: C.Color) void {
            const font_size_f32: f32 = @floatFromInt(self.font_size);

            // const txt_height = self.txt_size.y;

            // const y_top = switch (text_align.y) {
            //     .Center => bounds.y + bounds.height / 2 - txt_height / 2,
            //     .Start => bounds.y,
            //     .End => bounds.y + bounds.height - txt_height,
            // };

            var txt_mut = self.txt;
            var i: usize = 0;

            while (txt_mut.len > 0) : (i += 1) {
                var line_char_count: usize = undefined;
                const txt_width: f32 = @floatFromInt(measureLine(T, txt_mut, self.bounds, self.font_size, &line_char_count));

                const line = txt_mut[0..line_char_count];

                txt_mut = txt_mut[line_char_count..];

                // const x_left = switch (text_align.x) {
                //     .Center => bounds.x + bounds.width / 2 - txt_width / 2,
                //     .Start => bounds.x,
                //     .End => bounds.x + bounds.width - txt_width,
                // };

                var x_offset: f32 = align_bounds.x;

                for (line) |codepoint| {
                    switch (codepoint) {
                        '\r', '\n' => break,
                        else => {},
                    }
                    const font = Font.getCharFont(codepoint, self.font_size);
                    const glyph = C.GetGlyphInfo(font, codepoint);
                    C.DrawTextCodepoint(font, codepoint, .{ .x = x_offset, .y = y_top + @as(f32, @floatFromInt(i)) * font_size_f32 * 1.5 }, font_size_f32, tint);
                    x_offset += @floatFromInt(glyph.advanceX + Font.SPACING);
                }
            }
        }

        fn isFontSizeFitting(txt: []const T, bounds: C.Rectangle, fontSize: c_int) bool {
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
    };
}
