const std = @import("std");
const C = @import("c.zig").C;
const txt_input = @import("text_input.zig");
const GUI = @import("../gui.zig");
const api = @import("../api.zig");
const Font = @import("font.zig");

const allocator = std.heap.page_allocator;

pub fn handle_auth(stream: std.net.Stream) !std.crypto.dh.X25519.KeyPair {
    var keypair: ?std.crypto.dh.X25519.KeyPair = null;
    var passphrase: [:0]c_int = try allocator.allocSentinel(c_int, 0, 0);

    while (!C.WindowShouldClose() and keypair == null) {
        C.BeginDrawing();
        defer C.EndDrawing();

        C.ClearBackground(C.BLACK);

        GUI.WIDTH = @intCast(C.GetScreenWidth());
        GUI.HEIGHT = @intCast(C.GetScreenHeight());

        if (passphrase.len >= 32) {
            if (C.IsKeyPressed(C.KEY_ENTER) or C.IsKeyPressedRepeat(C.KEY_ENTER)) {
                try auth(&keypair, stream, passphrase);
            }
        }

        try draw_auth_screen(&passphrase, &keypair, stream);
    }

    if (C.WindowShouldClose()) std.process.exit(0);

    return keypair.?;
}

fn draw_auth_screen(passphrase: *[:0]c_int, keypair: *?std.crypto.dh.X25519.KeyPair, stream: std.net.Stream) !void {
    const x_center = @divTrunc(GUI.WIDTH, 2);

    try txt_input.draw_text_input(x_center, @divTrunc(GUI.HEIGHT, 3), .{ .UTF8 = @ptrCast(passphrase) }, GUI.FONT_SIZE, .Center);

    const auth_button_text = "Authenticate";
    const auth_button_text_length = Font.measureText(auth_button_text, GUI.FONT_SIZE);

    const auth_button = C.Rectangle{
        .x = @floatFromInt(x_center - @divTrunc(auth_button_text_length, 2) - GUI.button_padding),
        .y = @floatFromInt(@divTrunc(GUI.HEIGHT, 3) + GUI.FONT_SIZE + 20),
        .width = @floatFromInt(auth_button_text_length + GUI.button_padding * 2),
        .height = GUI.FONT_SIZE + GUI.button_padding * 2,
    };

    var button_color = C.BLUE;

    if (passphrase.len < 32) {
        button_color = C.GRAY;
    } else if (C.CheckCollisionPointRec(C.GetMousePosition(), auth_button)) {
        button_color = C.DARKBLUE;

        if (C.IsMouseButtonDown(C.MOUSE_LEFT_BUTTON)) {
            button_color = C.DARKPURPLE;
        }

        if (C.IsMouseButtonPressed(C.MOUSE_LEFT_BUTTON)) {
            try auth(keypair, stream, passphrase.*);
        }
    }

    C.DrawRectangleRec(auth_button, button_color);
    Font.drawText(auth_button_text, @intFromFloat(auth_button.x + GUI.button_padding), @intFromFloat(auth_button.y + GUI.button_padding), GUI.FONT_SIZE, C.WHITE);
}

fn auth(keypair: *?std.crypto.dh.X25519.KeyPair, stream: std.net.Stream, passphrase: [:0]c_int) !void {
    const passphrase_utf8 = C.LoadUTF8(passphrase.ptr, @intCast(passphrase.len));
    defer C.UnloadUTF8(passphrase_utf8);
    const len: u64 = @intCast(C.TextLength(passphrase_utf8));

    const derived = try @import("../crypto.zig").derive(passphrase_utf8[0..len]);

    keypair.* = try api.auth(stream, derived);
}
