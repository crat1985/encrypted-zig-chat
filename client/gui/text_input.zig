const C = @import("c.zig").C;
const GUI = @import("../gui.zig");
const std = @import("std");

const allocator = std.heap.page_allocator;

pub fn draw_text_input_array(comptime n: usize, center_x: c_int, y: c_int, txt: *[n:0]u8, index: *usize) void {
    if (C.IsKeyPressed(C.KEY_DELETE) or C.IsKeyPressedRepeat(C.KEY_DELETE)) blk: {
        if (index.* == 0) break :blk;
        index.* -= 1;
    }

    if (index.* == n) return;

    switch (C.GetCharPressed()) {
        0 => {},
        1...127 => |c| {
            const ascii_c: u8 = @intCast(c);
            txt.*[index.*] = ascii_c;
            index.* += 1;
        },
        else => |c| std.log.err("Unsupported character {u}", .{@as(u21, @intCast(c))}),
    }

    var txt_mut: [:0]u8 = txt[0..];

    draw_text_input_no_events(center_x, y, &txt_mut);
}

pub fn draw_text_input(center_x: c_int, y: c_int, txt: *[:0]u8) !void {
    try handle_potential_text_growth(txt);
    try handle_potential_text_reduction(txt);

    draw_text_input_no_events(center_x, y, txt);
}

fn draw_text_input_no_events(center_x: c_int, y: c_int, txt: *[:0]u8) void {
    const txt_length = C.MeasureText(txt.ptr, GUI.FONT_SIZE);

    const x1 = @as(u64, @intCast(center_x)) - (@abs(@as(i64, txt_length)) / 2);

    C.DrawText(txt.ptr, @intCast(x1), @intCast(y), GUI.FONT_SIZE, C.WHITE);
}

fn handle_potential_text_growth(txt: *[:0]u8) !void {
    const c: u21 = @intCast(C.GetCharPressed());
    if (c == 0) return;

    // std.log.info("\n\n\n\nKey = {d}\n\n\n\n", .{C.GetKeyPressed()});

    switch (c) {
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
    }
}

fn handle_potential_text_reduction(txt: *[:0]u8) !void {
    if (C.IsKeyPressed(C.KEY_BACKSPACE) or C.IsKeyPressedRepeat(C.KEY_BACKSPACE)) {
        if (txt.len == 0) return;

        const new_username = try allocator.allocSentinel(u8, txt.len - 1, 0);
        @memcpy(new_username, txt.*[0..new_username.len]);
        allocator.free(txt.*);
        txt.* = new_username;
    }
}
