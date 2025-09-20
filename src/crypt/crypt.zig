const std = @import("std");

pub const aes = std.crypto.aead.aes_gcm.Aes256Gcm;

pub const salt_lenght = 8;
pub const key_length = 16;
