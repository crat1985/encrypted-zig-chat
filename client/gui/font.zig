const C = @import("c.zig").C;
const std = @import("std");
const GUI = @import("../gui.zig");

// pub const SPACING = GUI.FONT_SIZE / 10;
pub const SPACING = 0;

var loaded_fonts: [100]struct { kind: FontKind, size: c_int, font: C.Font } = undefined;
var loaded_fonts_count: usize = 0;

pub fn getOrLoadFont(kind: FontKind, size: c_int) C.Font {
    for (loaded_fonts) |loaded_font| {
        if (loaded_font.kind != kind) continue;
        if (loaded_font.size != size) continue;
        return loaded_font.font;
    }

    const font_data = switch (kind) {
        .SansRegular => NotoSansRegular,
        .SymbolsRegular => NotoSansSymbolsRegular,
        .Symbols2Regular => NotoSansSymbols2Regular,
        .SansMathRegular => NotoSansMathRegular,
    };

    //TODO perhaps handle "index out of range" error better
    const new_font = C.LoadFontFromMemory(".ttf", font_data, @intCast(font_data.len), size, null, 1000);
    loaded_fonts[loaded_fonts_count] = .{ .kind = kind, .size = size, .font = new_font };
    loaded_fonts_count += 1;
    return new_font;
}

pub fn getCharFont(c: c_int, size: c_int) C.Font {
    const c_u21: u21 = @intCast(c);
    const font_kind = switch (c_u21) {
        0...0x7F,
        0x80...0xFF,
        0x100...0x17F,
        0x180...0x024F,
        0x0250...0x02AF,
        0x02B0...0x02FF,
        0x0300...0x036F,
        0x0370...0x03FF,
        0x0400...0x04FF,
        0x0500...0x052F,
        0x1E00...0x1EFF,
        0x2000...0x206F,
        0x20A0...0x20CF,
        0x2100...0x214F,
        => FontKind.SansRegular,
        0x2190...0x21FF,
        0x2200...0x22FF,
        0x2300...0x23FF,
        0x2400...0x243F,
        0x2440...0x245F,
        0x25A0...0x25FF,
        0x2600...0x26FF,
        0x2700...0x27BF,
        => FontKind.SymbolsRegular,
        0x1F000...0x1F02F,
        0x1F030...0x1F09F,
        0x1F0A0...0x1F0FF,
        0x1F100...0x1F1FF,
        0x1F200...0x1F2FF,
        0x1F300...0x1F5FF,
        => FontKind.Symbols2Regular,
        // 0x2200...0x22FF,
        0x27C0...0x27EF,
        0x2980...0x29FF,
        0x1D400...0x1D7FF,
        0x1D800...0x1DAAF,
        => FontKind.SansMathRegular,
        else => std.debug.panic("Unsupported characteur `{u}`", .{c_u21}),
    };

    return getOrLoadFont(font_kind, size);
}

pub const FontKind = enum(u8) {
    SansRegular,
    SymbolsRegular,
    Symbols2Regular,
    SansMathRegular,
};

/// * U+0000–U+007F
/// * U+0080–U+00FF
/// * U+0100–U+017F
/// * U+0180–U+024F
/// * U+0250–U+02AF
/// * U+02B0–U+02FF
/// * U+0300–U+036F
/// * U+0370–U+03FF
/// * U+0400–U+04FF
/// * U+0500–U+052F
/// * U+1E00–U+1EFF
/// * U+2000–U+206F
/// * U+20A0–U+20CF
/// * U+2100–U+214F
const NotoSansRegular = @embedFile("../../fonts/NotoSans-Regular.ttf");
/// * U+2190–U+21FF
/// * U+2200–U+22FF
/// * U+2300–U+23FF
/// * U+2400–U+243F
/// * U+2440–U+245F
/// * U+25A0–U+25FF
/// * U+2600–U+26FF
/// * U+2700–U+27BF
const NotoSansSymbolsRegular = @embedFile("../../fonts/NotoSansSymbols-Regular.ttf");
/// * U+1F000–U+1F02F
/// * U+1F030–U+1F09F
/// * U+1F0A0–U+1F0FF
/// * U+1F100–U+1F1FF
/// * U+1F200–U+1F2FF
/// * U+1F300–U+1F5FF
const NotoSansSymbols2Regular = @embedFile("../../fonts/NotoSansSymbols2-Regular.ttf");
/// * U+2200–U+22FF
/// * U+27C0–U+27EF
/// * U+2980–U+29FF
/// * U+1D400–U+1D7FF
/// * U+1D800–U+1DAAF
const NotoSansMathRegular = @embedFile("../../fonts/NotoSansMath-Regular.ttf");

pub fn measureCodepoints(txt: []const c_int, fontSize: c_int) c_int {
    var total_width: c_int = 0.0;

    for (txt) |codepoint| {
        const font = getCharFont(codepoint, fontSize);
        const glyph = C.GetGlyphInfo(font, codepoint);
        total_width += glyph.advanceX + SPACING;
    }

    return total_width;
}

pub fn drawCodepoints(txt: []const c_int, fontSize: c_int, x: c_int, y: c_int, tint: C.Color) void {
    var x_offset = x;
    var y_offset = y;

    for (txt) |codepoint| {
        switch (codepoint) {
            '\r' => {
                x_offset = x;
                continue;
            },
            '\n' => {
                x_offset = x;
                y_offset += @divTrunc(fontSize * 5, 4);
                continue;
            },
            else => {},
        }
        const font = getCharFont(codepoint, fontSize);
        const glyph = C.GetGlyphInfo(font, codepoint);
        C.DrawTextCodepoint(font, codepoint, .{ .x = @floatFromInt(x_offset), .y = @floatFromInt(y_offset) }, @floatFromInt(fontSize), tint);
        x_offset += glyph.advanceX + SPACING;
    }
}
