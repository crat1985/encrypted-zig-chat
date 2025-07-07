const EncryptedPart = @import("../message/encrypted.zig").EncryptedPart;

pub const DECRYPTED_OUTPUT_DIR = "decrypted_files";
pub const BLOCK_SIZE = 4000;
pub const FULL_MESSAGE_SIZE = BLOCK_SIZE + 60;
pub const ACTION_DATA_SIZE = BLOCK_SIZE - @sizeOf(EncryptedPart.ActionKind) - 8;
pub const PAYLOAD_AND_PADDING_SIZE = ACTION_DATA_SIZE - 4;
