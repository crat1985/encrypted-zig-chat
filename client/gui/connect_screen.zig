const std = @import("std");
const C = @import("c.zig").C;
const GUI = @import("../gui.zig");
const txt_input = @import("text_input.zig");
const Font = @import("font.zig");

const allocator = std.heap.page_allocator;

pub fn connect_to_server() !std.net.Stream {
    var server_addr = allocator.alloc(u8, 0) catch unreachable;
    var server: ?std.net.Stream = null;

    while (!C.WindowShouldClose() and server == null) {
        C.BeginDrawing();
        defer C.EndDrawing();

        C.ClearBackground(C.BLACK);

        GUI.WIDTH = @floatFromInt(C.GetScreenWidth());
        GUI.HEIGHT = @floatFromInt(C.GetScreenHeight());

        const bounds = C.Rectangle{
            .x = 0,
            .y = 0,
            .width = GUI.WIDTH,
            .height = GUI.HEIGHT,
        };

        try draw_connect_to_server_screen(&server_addr, &server, bounds);

        if (C.IsKeyPressed(C.KEY_ENTER)) {
            try connect_to_server_button_clicked(&server_addr, &server);
        }
    }

    if (C.WindowShouldClose()) std.process.exit(0);

    return server.?;
}

fn draw_connect_to_server_screen(server_addr: *[]u8, server: *?std.net.Stream, bounds: C.Rectangle) !void {
    var txt_input_bounds = C.Rectangle{
        .x = bounds.x,
        .y = bounds.y + bounds.height * 2 / 6,
        .width = bounds.width,
        .height = bounds.height * 2 / 6,
    };

    const ConnectButtonText = "Connect";

    try txt_input.draw_text_input(txt_input_bounds, .{ .ASCII = server_addr }, GUI.FONT_SIZE, .Center, .Center);

    txt_input_bounds.y += txt_input_bounds.height;
    txt_input_bounds.height = bounds.height / 6;

    const connect_button = Font.getRealTextRect(txt_input_bounds, GUI.button_padding, GUI.button_padding, GUI.FONT_SIZE, .{ .Bytes = ConnectButtonText }, .Center, .Center);

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

    Font.drawDefaultButtonTextRect(txt_input_bounds, C.WHITE, C.BLUE, .{ .Bytes = ConnectButtonText });
}

const DEFAULT_ADDR = std.net.Address.initIp4(.{ 127, 0, 0, 1 }, 8080);

fn connect_to_server_button_clicked(server_addr: *[]u8, server: *?std.net.Stream) !void {
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
