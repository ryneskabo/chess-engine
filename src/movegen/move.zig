const std = @import("std");
const brd = @import("../board.zig");

const Piece = brd.Piece;

pub const MoveFlags = enum(u4) {
    quiet_move = 0b0000,
    double_pawn_push = 0b0001,
    kingside_castle = 0b0010,
    queenside_castle = 0b0011,
    capture = 0b0100,
    en_passant_capture = 0b0101,
    knight_promotion = 0b1000,
    bishop_promotion = 0b1001,
    rook_promotion = 0b1010,
    queen_promotion = 0b1011,
    knight_promotion_capture = 0b1100,
    bishop_promotion_capture = 0b1101,
    rook_promotion_capture = 0b1110,
    queen_promotion_capture = 0b1111,

    pub fn isPromotion(self: MoveFlags) bool {
        return @backingInt(self) & @as(u4, 0b1000) != 0;
    }

    pub fn isCapture(self: MoveFlags) bool {
        return @backingInt(self) & @as(u4, 0b0100) != 0;
    }

    pub fn piecePromoted(self: MoveFlags) ?Piece {
        if (!self.isPromotion()) return null;

        return switch (@backingInt(self) & @as(u4, 0b0011)) {
            0b0000 => .knight,
            0b0001 => .bishop,
            0b0010 => .rook,
            0b0011 => .queen,
            else => unreachable, // verify this
        };
    }
};

pub const Move = packed struct(u16) {
    from: brd.Square,
    to: brd.Square,
    flags: MoveFlags,
};

pub const MoveList = struct {
    moves: [256]Move = undefined,
    count: u16 = 0, // Avoiding overflow

    pub fn add(self: *MoveList, move: Move) void {
        std.debug.assert(self.count < self.moves.len);

        self.moves[self.count] = move;
        self.count += 1;
    }
};

const quiet_promotion_flags = [_]MoveFlags{
    .knight_promotion,
    .bishop_promotion,
    .rook_promotion,
    .queen_promotion,
};

const capture_promotion_flags = [_]MoveFlags{
    .knight_promotion_capture,
    .bishop_promotion_capture,
    .rook_promotion_capture,
    .queen_promotion_capture,
};

/// Emits all four promotion moves (knight, bishop, rook, queen) for a pawn moving
/// from `from` to `to`, using either quiet or capture promotion flags.
pub fn addPromotionMoves(move_list: *MoveList, from: brd.Square, to: brd.Square, is_capture: bool) void {
    const flags = if (is_capture) capture_promotion_flags else quiet_promotion_flags;
    for (flags) |flag| {
        move_list.add(.{
            .from = from,
            .to = to,
            .flags = flag,
        });
    }
}

pub fn addMovesFromTargets(move_list: *MoveList, from: brd.Square, targets: u64, opponent_occupancy: u64) void {
    var captures = targets & opponent_occupancy;
    var quiet_moves = targets & ~opponent_occupancy;

    while (quiet_moves != 0) : (quiet_moves &= quiet_moves - 1) {
        const target_square: brd.Square = @intCast(@ctz(quiet_moves));
        move_list.add(.{
            .from = from,
            .to = target_square,
            .flags = .quiet_move,
        });
    }

    while (captures != 0) : (captures &= captures - 1) {
        const target_square: brd.Square = @intCast(@ctz(captures));
        move_list.add(.{
            .from = from,
            .to = target_square,
            .flags = .capture,
        });
    }
}

test "Move size is 2 bytes" {
    try std.testing.expectEqual(@as(usize, 2), @sizeOf(Move));
    try std.testing.expectEqual(@as(usize, 16), @bitSizeOf(Move));
}

test "Move round trip and packed bit layout" {
    const m = Move{
        .from = 12,
        .to = 28,
        .flags = .double_pawn_push,
    };

    try std.testing.expectEqual(@as(brd.Square, 12), m.from);
    try std.testing.expectEqual(@as(brd.Square, 28), m.to);
    try std.testing.expectEqual(MoveFlags.double_pawn_push, m.flags);

    // Packed structs place the first field (from) in the lowest bits:
    // bits 0..5 = from (12), bits 6..11 = to (28), bits 12..15 = flags (0b0001)
    const raw: u16 = @bitCast(m);
    const expected_raw: u16 = @as(u16, 12) | (@as(u16, 28) << 6) | (@as(u16, 0b0001) << 12);
    try std.testing.expectEqual(expected_raw, raw);

    const unpacked: Move = @bitCast(raw);
    try std.testing.expectEqual(m, unpacked);
}

test "Move extremes for squares and flags" {
    const min_move = Move{ .from = 0, .to = 0, .flags = .quiet_move };
    try std.testing.expectEqual(@as(u16, 0), @as(u16, @bitCast(min_move)));
    try std.testing.expectEqual(@as(brd.Square, 0), min_move.from);
    try std.testing.expectEqual(@as(brd.Square, 0), min_move.to);
    try std.testing.expectEqual(MoveFlags.quiet_move, min_move.flags);

    const max_move = Move{ .from = 63, .to = 63, .flags = .queen_promotion_capture };
    try std.testing.expectEqual(@as(u16, 0xFFFF), @as(u16, @bitCast(max_move)));
    try std.testing.expectEqual(@as(brd.Square, 63), max_move.from);
    try std.testing.expectEqual(@as(brd.Square, 63), max_move.to);
    try std.testing.expectEqual(MoveFlags.queen_promotion_capture, max_move.flags);
}

test "MoveFlags capture and promotion helpers" {
    try std.testing.expect(!MoveFlags.quiet_move.isCapture());
    try std.testing.expect(!MoveFlags.quiet_move.isPromotion());
    try std.testing.expectEqual(@as(?Piece, null), MoveFlags.quiet_move.piecePromoted());

    try std.testing.expect(!MoveFlags.double_pawn_push.isCapture());
    try std.testing.expect(!MoveFlags.kingside_castle.isCapture());
    try std.testing.expect(!MoveFlags.queenside_castle.isCapture());

    // Non-promotion captures
    try std.testing.expect(MoveFlags.capture.isCapture());
    try std.testing.expect(!MoveFlags.capture.isPromotion());
    try std.testing.expectEqual(@as(?Piece, null), MoveFlags.capture.piecePromoted());

    try std.testing.expect(MoveFlags.en_passant_capture.isCapture());
    try std.testing.expect(!MoveFlags.en_passant_capture.isPromotion());
    try std.testing.expectEqual(@as(?Piece, null), MoveFlags.en_passant_capture.piecePromoted());

    // Quiet promotions
    const quiet_promos = [_]struct { flag: MoveFlags, piece: Piece }{
        .{ .flag = .knight_promotion, .piece = .knight },
        .{ .flag = .bishop_promotion, .piece = .bishop },
        .{ .flag = .rook_promotion, .piece = .rook },
        .{ .flag = .queen_promotion, .piece = .queen },
    };
    for (quiet_promos) |case| {
        try std.testing.expect(case.flag.isPromotion());
        try std.testing.expect(!case.flag.isCapture());
        try std.testing.expectEqual(@as(?Piece, case.piece), case.flag.piecePromoted());
    }

    // Capture promotions
    const capture_promos = [_]struct { flag: MoveFlags, piece: Piece }{
        .{ .flag = .knight_promotion_capture, .piece = .knight },
        .{ .flag = .bishop_promotion_capture, .piece = .bishop },
        .{ .flag = .rook_promotion_capture, .piece = .rook },
        .{ .flag = .queen_promotion_capture, .piece = .queen },
    };
    for (capture_promos) |case| {
        try std.testing.expect(case.flag.isPromotion());
        try std.testing.expect(case.flag.isCapture());
        try std.testing.expectEqual(@as(?Piece, case.piece), case.flag.piecePromoted());
    }
}

test "MoveList starts empty and adds three moves" {
    var list = MoveList{};
    try std.testing.expectEqual(@as(u16, 0), list.count);

    const m1 = Move{ .from = 12, .to = 28, .flags = .double_pawn_push }; // e2e4
    const m2 = Move{ .from = 6, .to = 21, .flags = .quiet_move }; // g1f3
    const m3 = Move{ .from = 28, .to = 35, .flags = .capture }; // e4xd5

    list.add(m1);
    list.add(m2);
    list.add(m3);

    try std.testing.expectEqual(@as(u16, 3), list.count);
    try std.testing.expectEqual(m1, list.moves[0]);
    try std.testing.expectEqual(m2, list.moves[1]);
    try std.testing.expectEqual(m3, list.moves[2]);
}
