const C = @import("c.zig").C;
const GUI = @import("../gui.zig");
const std = @import("std");
const Font = @import("font.zig");

const allocator = std.heap.page_allocator;

pub const Alignment = enum(u8) {
    Center,
    Left,
};

pub const TxtKind = union(enum(u8)) {
    ASCII: *[:0]u8,
    UTF8: *[:0]c_int,
};

pub fn draw_text_input_array(comptime n: usize, align_x: c_int, y: c_int, txt: *[n:0]u8, index: *usize, alignment: Alignment) void {
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

    draw_text_input_no_events(align_x, y, .{ .ASCII = &txt_mut }, GUI.FONT_SIZE, alignment);
}

pub fn draw_text_input(align_x: c_int, y: c_int, txt: TxtKind, font_size: c_int, alignment: Alignment) !void {
    try handle_potential_text_growth(txt);
    try handle_potential_text_reduction(txt);

    draw_text_input_no_events(align_x, y, txt, font_size, alignment);
}

fn draw_text_input_no_events(align_x: c_int, y: c_int, txt: TxtKind, font_size: c_int, alignment: Alignment) void {
    const txt_length = switch (txt) {
        .ASCII => |txt_ptr| C.MeasureText(txt_ptr.ptr, font_size),
        .UTF8 => |txt_ptr| Font.measureCodepoints(txt_ptr.*, font_size),
    };

    const x1 = switch (alignment) {
        .Center => align_x - @divTrunc(txt_length, 2),
        .Left => align_x,
    };

    switch (txt) {
        .ASCII => |txt_ptr| C.DrawText(txt_ptr.ptr, x1, y, font_size, C.WHITE),
        .UTF8 => |txt_ptr| Font.drawCodepoints(txt_ptr.*, font_size, x1, y, C.WHITE),
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
