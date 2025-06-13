const std = @import("std");
const C = @import("c.zig").C;
const txt_input = @import("text_input.zig");
const GUI = @import("../gui.zig");
const api = @import("../api.zig");

const allocator = std.heap.page_allocator;

pub fn handle_auth(stream: std.net.Stream) !std.crypto.dh.X25519.KeyPair {
    var keypair: ?std.crypto.dh.X25519.KeyPair = null;
    var passphrase: [:0]u8 = try allocator.allocSentinel(u8, 0, 0);

    while (!C.WindowShouldClose() and keypair == null) {
        C.BeginDrawing();
        defer C.EndDrawing();

        C.ClearBackground(C.BLACK);

        GUI.WIDTH = @intCast(C.GetScreenWidth());
        GUI.HEIGHT = @intCast(C.GetScreenHeight());

        if (C.IsKeyPressed(C.KEY_ENTER) or C.IsKeyPressedRepeat(C.KEY_ENTER)) {
            try auth(&keypair, stream, passphrase);
        }

        try draw_auth_screen(&passphrase, &keypair, stream);
    }

    if (C.WindowShouldClose()) std.process.exit(0);

    return keypair.?;
}

fn draw_auth_screen(passphrase: *[:0]u8, keypair: *?std.crypto.dh.X25519.KeyPair, stream: std.net.Stream) !void {
    try txt_input.draw_text_input(@intCast(GUI.WIDTH / 2), @intCast(GUI.HEIGHT / 3), passphrase, GUI.FONT_SIZE);

    const auth_button_text = "Authenticate";
    const auth_button_text_length = C.MeasureText(auth_button_text, GUI.FONT_SIZE);

    const auth_button = C.Rectangle{
        .x = @floatFromInt((GUI.WIDTH / 2) - @as(u64, @intCast(auth_button_text_length)) / 2 - GUI.button_padding),
        .y = @floatFromInt(GUI.HEIGHT / 3 + GUI.FONT_SIZE + 20),
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
    C.DrawText(auth_button_text, @intFromFloat(auth_button.x + GUI.button_padding), @intFromFloat(auth_button.y + GUI.button_padding), GUI.FONT_SIZE, C.WHITE);
}

fn auth(keypair: *?std.crypto.dh.X25519.KeyPair, stream: std.net.Stream, passphrase: []u8) !void {
    const derived = try @import("../crypto.zig").derive(passphrase);

    keypair.* = try api.auth(stream, derived);
}
