const std = @import("std");
const C = @import("c.zig").C;
const GUI = @import("../gui.zig");
const txt_input = @import("text_input.zig");

const allocator = std.heap.page_allocator;

pub fn connect_to_server() !std.net.Stream {
    var server_addr: [:0]u8 = allocator.allocSentinel(u8, 0, 0) catch unreachable;
    var server: ?std.net.Stream = null;

    while (!C.WindowShouldClose() and server == null) {
        C.BeginDrawing();
        defer C.EndDrawing();

        GUI.WIDTH = @intCast(C.GetScreenWidth());
        GUI.HEIGHT = @intCast(C.GetScreenHeight());

        try draw_connect_to_server_screen(&server_addr, &server);

        if (C.IsKeyPressed(C.KEY_ENTER) or C.IsKeyPressedRepeat(C.KEY_ENTER)) {
            try connect_to_server_button_clicked(&server_addr, &server);
        }
    }

    if (C.WindowShouldClose()) std.process.exit(0);

    return server.?;
}

fn draw_connect_to_server_screen(server_addr: *[:0]u8, server: *?std.net.Stream) !void {
    const ConnectButtonText = "Connect";
    const connect_button_length = C.MeasureText(ConnectButtonText, 30);

    C.ClearBackground(C.BLACK);

    const x1_center = GUI.WIDTH / 2;
    const y1 = GUI.HEIGHT / 3;
    try txt_input.draw_text_input(@intCast(x1_center), @intCast(y1), server_addr);

    const connect_button = C.Rectangle{
        .x = @floatFromInt((GUI.WIDTH / 2) - (@abs(@as(i64, connect_button_length)) / 2) - GUI.button_padding),
        .y = @floatFromInt(y1 + GUI.FONT_SIZE + 20),
        .width = @floatFromInt(connect_button_length + GUI.button_padding * 2),
        .height = @floatFromInt(GUI.FONT_SIZE + GUI.button_padding * 2),
    };

    var button_color = C.BLUE;

    if (C.CheckCollisionPointRec(C.GetMousePosition(), connect_button)) {
        button_color = C.DARKBLUE;
        if (C.IsMouseButtonDown(C.MOUSE_LEFT_BUTTON)) {
            button_color = C.DARKPURPLE;
        }
        if (C.IsMouseButtonPressed(C.MOUSE_LEFT_BUTTON)) {
            try connect_to_server_button_clicked(server_addr, server);
        }
    }

    C.DrawRectangleRec(connect_button, button_color);

    const button_text_x1 = (GUI.WIDTH / 2) - (@abs(@as(i64, connect_button_length)) / 2);
    const button_text_y1 = connect_button.y + GUI.button_padding;

    C.DrawText(ConnectButtonText, @intCast(button_text_x1), @intFromFloat(button_text_y1), GUI.FONT_SIZE, C.WHITE);
}

const DEFAULT_ADDR = std.net.Address.initIp4(.{ 127, 0, 0, 1 }, 8080);

fn connect_to_server_button_clicked(server_addr: *[:0]u8, server: *?std.net.Stream) !void {
    if (server_addr.len == 0) {
        server.* = std.net.tcpConnectToAddress(DEFAULT_ADDR) catch |err| return std.log.err("Error connecting to the server : {}", .{err});
        return;
    }

    var iterator = std.mem.splitScalar(u8, server_addr.*, ':');
    const host = iterator.next().?;
    const port: u16 = blk2: {
        const port = iterator.next() orelse break :blk2 8080;
        break :blk2 try std.fmt.parseInt(u16, port, 10);
    };
    std.log.info("Trying to connect to {s}:{d}...", .{ host, port });
    server.* = std.net.tcpConnectToHost(allocator, host, port) catch |err| return std.log.err("Error connecting to the server : {}", .{err});
}
