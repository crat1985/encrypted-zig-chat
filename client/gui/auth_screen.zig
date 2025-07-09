const std = @import("std");
const C = @import("c.zig").C;
const txt_input = @import("text_input.zig");
const GUI = @import("../gui.zig");
const api = @import("../api.zig");
const Font = @import("font.zig");

const allocator = std.heap.page_allocator;

pub fn handle_auth(reader: std.io.AnyReader) !std.crypto.dh.X25519.KeyPair {
    var keypair: ?std.crypto.dh.X25519.KeyPair = null;
    var passphrase: [:0]c_int = try allocator.allocSentinel(c_int, 0, 0);

    while (!C.WindowShouldClose() and keypair == null) {
        C.BeginDrawing();
        defer C.EndDrawing();

        C.ClearBackground(C.BLACK);

        GUI.WIDTH = @floatFromInt(C.GetScreenWidth());
        GUI.HEIGHT = @floatFromInt(C.GetScreenHeight());

        if (passphrase.len >= 32) {
            if (C.IsKeyPressed(C.KEY_ENTER)) {
                try auth(&keypair, passphrase, reader);
            }
        }

        const bounds = C.Rectangle{
            .x = 0,
            .y = 0,
            .width = GUI.WIDTH,
            .height = GUI.HEIGHT,
        };

        try draw_auth_screen(&passphrase, &keypair, reader, bounds);
    }

    if (C.WindowShouldClose()) std.process.exit(0);

    return keypair.?;
}

fn draw_auth_screen(passphrase: *[:0]c_int, keypair: *?std.crypto.dh.X25519.KeyPair, reader: std.io.AnyReader, bounds: C.Rectangle) !void {
    var txt_input_bounds = C.Rectangle{
        .x = bounds.x,
        .y = bounds.y + bounds.height * 2 / 6,
        .width = bounds.width,
        .height = bounds.height / 6,
    };

    try txt_input.draw_text_input(txt_input_bounds, .{ .UTF8 = @ptrCast(passphrase) }, GUI.FONT_SIZE, .Center, .Center);

    txt_input_bounds.y += txt_input_bounds.height;

    const auth_button_text = "Authenticate";

    const auth_button = Font.getRealTextRect(txt_input_bounds, GUI.button_padding, GUI.button_padding, GUI.FONT_SIZE, .{ .Bytes = auth_button_text }, .Center, .Center);

    var button_color = C.BLUE;

    if (passphrase.len < 32) {
        button_color = C.GRAY;
    } else if (C.CheckCollisionPointRec(C.GetMousePosition(), auth_button)) {
        button_color = C.DARKBLUE;

        if (C.IsMouseButtonDown(C.MOUSE_LEFT_BUTTON)) {
            button_color = C.DARKPURPLE;
        }

        if (C.IsMouseButtonPressed(C.MOUSE_LEFT_BUTTON)) {
            try auth(keypair, passphrase.*, reader);
        }
    }

    C.DrawRectangleRec(auth_button, button_color);
    Font.drawText(auth_button_text, auth_button, GUI.FONT_SIZE, C.WHITE, .Center, .Center);
}

fn auth(keypair: *?std.crypto.dh.X25519.KeyPair, passphrase: [:0]c_int, reader: std.io.AnyReader) !void {
    const passphrase_utf8 = C.LoadUTF8(passphrase.ptr, @intCast(passphrase.len));
    defer C.UnloadUTF8(passphrase_utf8);
    const len: u64 = @intCast(C.TextLength(passphrase_utf8));

    const derived = try @import("../crypto.zig").derive(passphrase_utf8[0..len]);

    keypair.* = try api.auth.auth(derived, reader);
}
