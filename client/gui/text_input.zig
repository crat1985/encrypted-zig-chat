const C = @import("c.zig").C;
const GUI = @import("../gui.zig");
const std = @import("std");
const Font = @import("font.zig");

const Alignment = Font.Alignment;

const allocator = std.heap.page_allocator;

pub const TxtKind = union(enum(u8)) {
    ASCII: *[]u8,
    UTF8: *[]c_int,
};

pub fn draw_text_input_array(comptime n: usize, bounds: C.Rectangle, txt: *[n:0]u8, index: *usize, h_align: Alignment, v_align: Alignment, max_font_size: c_int) void {
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

    Font.drawText(txt, bounds, max_font_size, C.WHITE, h_align, v_align);
}

pub fn draw_text_input(bounds: C.Rectangle, txt: TxtKind, max_font_size: c_int, h_align: Alignment, v_align: Alignment) !void {
    try handle_potential_text_growth(txt);
    try handle_potential_text_reduction(txt);

    switch (txt) {
        .ASCII => |msg| Font.drawText(msg.*, bounds, max_font_size, C.WHITE, h_align, v_align),
        .UTF8 => |msg| Font.drawCodepoints(msg.*, bounds, max_font_size, C.WHITE, h_align, v_align),
    }
}

fn handle_potential_text_growth(txt: TxtKind) !void {
    const c: u21 = @intCast(C.GetCharPressed());
    if (c == 0) return;

    switch (txt) {
        .ASCII => |txt_ptr| switch (c) {
            //Handle ASCII chars
            0...127 => {
                const ascii_c: u8 = @intCast(c);
                const new_username = try allocator.allocSentinel(u8, txt_ptr.len + 1, 0);
                @memcpy(new_username[0..txt_ptr.len], txt_ptr.*);
                new_username[txt_ptr.len] = ascii_c;
                allocator.free(txt_ptr.*);
                txt_ptr.* = new_username;
            },
            else => std.log.err("Unsupported character {u}", .{c}),
        },
        .UTF8 => |txt_ptr| {
            const new_username = try allocator.allocSentinel(c_int, txt_ptr.len + 1, 0);
            @memcpy(new_username[0..txt_ptr.len], txt_ptr.*);
            new_username[txt_ptr.len] = c;
            allocator.free(txt_ptr.*);
            txt_ptr.* = new_username;
        },
    }
}

fn handle_potential_text_reduction(txt: TxtKind) !void {
    if (C.IsKeyPressed(C.KEY_BACKSPACE) or C.IsKeyPressedRepeat(C.KEY_BACKSPACE)) {
        switch (txt) {
            .ASCII => |txt_ptr| {
                if (txt_ptr.len == 0) return;
                const new_username = try allocator.allocSentinel(u8, txt_ptr.len - 1, 0);
                @memcpy(new_username, txt_ptr.*[0..new_username.len]);
                allocator.free(txt_ptr.*);
                txt_ptr.* = new_username;
            },
            .UTF8 => |txt_ptr| {
                if (txt_ptr.len == 0) return;
                const new_username = try allocator.allocSentinel(c_int, txt_ptr.len - 1, 0);
                @memcpy(new_username, txt_ptr.*[0..new_username.len]);
                allocator.free(txt_ptr.*);
                txt_ptr.* = new_username;
            },
        }
    }
}
