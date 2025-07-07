pub const auth = @import("api/auth.zig");
pub const data = @import("api/data.zig");
pub const listen = @import("api/listen.zig");
pub const request = @import("api/request.zig");

const socket = @import("api/socket.zig");
pub const init = socket.init;
pub const deinit = socket.deinit;
