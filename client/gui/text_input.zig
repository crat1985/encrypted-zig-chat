const C = @import("c.zig").C;
const GUI = @import("../gui.zig");
const std = @import("std");
const Font = @import("font.zig");
const txt_mod = @import("txt.zig");

const Alignment = txt_mod.Alignment;

const allocator = std.heap.page_allocator;

pub fn draw_text_input_array(comptime n: usize, comptime T: type, txt: *[n]T, bounds: C.Rectangle, index: *usize, h_align: Alignment, v_align: Alignment, max_font_size: c_int) void {
    if (C.IsKeyPressed(C.KEY_BACKSPACE) or C.IsKeyPressedRepeat(C.KEY_BACKSPACE)) blk: {
        if (index.* == 0) break :blk;
        index.* -= 1;
    }

    switch (C.GetCharPressed()) {
        0 => {},
        'a'...'z', 'A'...'Z', '0'...'9' => |c| {
            const ascii_c: u8 = @intCast(c);

            //TODO perhaps add a sound to say "no space left"
            if (index.* < n) {
                txt.*[index.*] = ascii_c;
                index.* += 1;
            }
        },
        else => |c| std.log.err("Unsupported character {u}", .{@as(u21, @intCast(c))}),
    }

    txt_mod.drawText(T, txt, bounds, max_font_size, C.WHITE, h_align, v_align);
}

pub fn draw_text_input(comptime T: type, txt: *[]T, bounds: C.Rectangle, max_font_size: c_int, h_align: Alignment, v_align: Alignment) !void {
    try handle_potential_text_growth(T, txt);
    try handle_potential_text_reduction(T, txt);

    txt_mod.drawText(T, txt.*, bounds, max_font_size, C.WHITE, h_align, v_align);
}

fn handle_potential_text_growth(comptime T: type, txt: *[]T) !void {
    const c: u21 = @intCast(C.GetCharPressed());
    if (c == 0) return;

    switch (T) {
        u8 => switch (c) {
            //Handle ASCII chars
            0...127 => {
                const ascii_c: u8 = @intCast(c);
                const new_username = try allocator.allocSentinel(u8, txt.len + 1, 0);
                @memcpy(new_username[0..txt.len], txt.*);
                new_username[txt.len] = ascii_c;
                allocator.free(txt.*);
                txt.* = new_username;
            },
            else => std.log.err("Unsupported character {u}", .{c}),
        },
        c_int => {
            const new_username = try allocator.allocSentinel(c_int, txt.len + 1, 0);
            @memcpy(new_username[0..txt.len], txt.*);
            new_username[txt.len] = c;
            allocator.free(txt.*);
            txt.* = new_username;
        },
        else => @compileError("Unsupported type " ++ @typeName(T)),
    }
}

fn handle_potential_text_reduction(comptime T: type, txt: *[]T) !void {
    if (C.IsKeyPressed(C.KEY_BACKSPACE) or C.IsKeyPressedRepeat(C.KEY_BACKSPACE)) {
        switch (T) {
            u8 => {
                if (txt.len == 0) return;
                const new_username = try allocator.allocSentinel(u8, txt.len - 1, 0);
                @memcpy(new_username, txt.*[0..new_username.len]);
                allocator.free(txt.*);
                txt.* = new_username;
            },
            c_int => {
                if (txt.len == 0) return;
                const new_username = try allocator.allocSentinel(c_int, txt.len - 1, 0);
                @memcpy(new_username, txt.*[0..new_username.len]);
                allocator.free(txt.*);
                txt.* = new_username;
            },
            else => @compileError("Unsupported type " ++ @typeName(T)),
        }
    }
}
