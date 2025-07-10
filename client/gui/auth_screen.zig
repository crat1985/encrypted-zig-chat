const std = @import("std");
const C = @import("c.zig").C;
const txt_input = @import("text_input.zig");
const GUI = @import("../gui.zig");
const api = @import("../api.zig");
const Font = @import("font.zig");
const Button = @import("button.zig").Button;

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

        var cursor = C.MOUSE_CURSOR_DEFAULT;
        defer C.SetMouseCursor(cursor);

        try draw_auth_screen(&passphrase, &keypair, reader, bounds, &cursor);
    }

    if (C.WindowShouldClose()) std.process.exit(0);

    return keypair.?;
}

fn draw_auth_screen(passphrase: *[:0]c_int, keypair: *?std.crypto.dh.X25519.KeyPair, reader: std.io.AnyReader, bounds: C.Rectangle, cursor: *c_int) !void {
    var txt_input_bounds = C.Rectangle{
        .x = bounds.x,
        .y = bounds.y + bounds.height * 2 / 6,
        .width = bounds.width,
        .height = bounds.height / 6,
    };

    try txt_input.draw_text_input(c_int, @ptrCast(passphrase), txt_input_bounds, GUI.FONT_SIZE, .Center, .Center);

    txt_input_bounds.y += txt_input_bounds.height;

    const auth_button_text = "Authenticate";

    const auth_button = Button(u8).init_default_text_button_center(txt_input_bounds, auth_button_text, passphrase.len >= 32);
    auth_button.set_cursor(cursor);
    auth_button.draw();

    if (auth_button.is_clicked()) {
        try auth(keypair, passphrase.*, reader);
    }
}

fn auth(keypair: *?std.crypto.dh.X25519.KeyPair, passphrase: [:0]c_int, reader: std.io.AnyReader) !void {
    const passphrase_utf8 = C.LoadUTF8(passphrase.ptr, @intCast(passphrase.len));
    defer C.UnloadUTF8(passphrase_utf8);
    const len: u64 = @intCast(C.TextLength(passphrase_utf8));

    const derived = try @import("../crypto.zig").derive(passphrase_utf8[0..len]);

    keypair.* = try api.auth.auth(derived, reader);
}
