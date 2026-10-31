const std = @import("std");
const fen = @import("fen.zig");
const brd = @import("board.zig");

const Board = brd.Board;
const Color = brd.Color;
const Piece = brd.Piece;

const rank_3: u64 = 0x0000000000FF0000;
const rank_6: u64 = 0x0000FF0000000000;
pub fn generatePawnPushes(board: *const Board, color: Color) struct { single: u64, double: u64 } {
    const occupied = board.occupancy[@backingInt(Color.white)] | board.occupancy[@backingInt(Color.black)];
    const empty = ~occupied;

    const pawns = board.pieces[@backingInt(color)][@backingInt(Piece.pawn)];
    if (color == .white) {
        const single_push = (pawns << 8) & empty;
        const double_push = ((single_push & rank_3) << 8) & empty;
        return .{ .single = single_push, .double = double_push };
    } else {
        const single_push = (pawns >> 8) & empty;
        const double_push = ((single_push & rank_6) >> 8) & empty;
        return .{ .single = single_push, .double = double_push };
    }
}

/// bit 2 on means capture, bit 3 means promotion, 0 indexed from LSB
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

pub fn singlePawnPushesToMoves(bit_board: u64, color: Color, move_list: *MoveList) void {
    var bb = bit_board;
    if (color == .white) {
        while (bb != 0) : (bb &= bb - 1) {
            const pawn_square: brd.Square = @intCast(@ctz(bb));
            if (pawn_square >= 56) {
                // emit four promotion moves, one per type
                move_list.add(.{
                    .from = pawn_square - 8,
                    .to = pawn_square,
                    .flags = .knight_promotion,
                });
                move_list.add(.{
                    .from = pawn_square - 8,
                    .to = pawn_square,
                    .flags = .bishop_promotion,
                });
                move_list.add(.{
                    .from = pawn_square - 8,
                    .to = pawn_square,
                    .flags = .rook_promotion,
                });
                move_list.add(.{
                    .from = pawn_square - 8,
                    .to = pawn_square,
                    .flags = .queen_promotion,
                });
                continue;
            }
            move_list.add(.{
                .from = pawn_square - 8,
                .to = pawn_square,
                .flags = .quiet_move,
            });
        }
    } else {
        while (bb != 0) : (bb &= bb - 1) {
            const pawn_square: brd.Square = @intCast(@ctz(bb));
            if (pawn_square <= 7) {
                // emit four promotion moves, one per type
                move_list.add(.{
                    .from = pawn_square + 8,
                    .to = pawn_square,
                    .flags = .knight_promotion,
                });
                move_list.add(.{
                    .from = pawn_square + 8,
                    .to = pawn_square,
                    .flags = .bishop_promotion,
                });
                move_list.add(.{
                    .from = pawn_square + 8,
                    .to = pawn_square,
                    .flags = .rook_promotion,
                });
                move_list.add(.{
                    .from = pawn_square + 8,
                    .to = pawn_square,
                    .flags = .queen_promotion,
                });
                continue;
            }
            move_list.add(.{
                .from = pawn_square + 8,
                .to = pawn_square,
                .flags = .quiet_move,
            });
        }
    }
}

pub fn doublePawnPushesToMoves(bit_board: u64, color: Color, move_list: *MoveList) void {
    var bb = bit_board;
    if (color == .white) {
        while (bb != 0) : (bb &= bb - 1) {
            const pawn_square: brd.Square = @intCast(@ctz(bb));
            move_list.add(.{
                .from = pawn_square - 16,
                .to = pawn_square,
                .flags = .double_pawn_push,
            });
        }
    } else {
        while (bb != 0) : (bb &= bb - 1) {
            const pawn_square: brd.Square = @intCast(@ctz(bb));
            move_list.add(.{
                .from = pawn_square + 16,
                .to = pawn_square,
                .flags = .double_pawn_push,
            });
        }
    }
}

const squareBit = brd.squareBit;

test "pushes from the starting position" {
    const b = try fen.parseFen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");

    const w = generatePawnPushes(&b, .white);
    try std.testing.expectEqual(@as(u64, 0x0000000000FF0000), w.single); // rank 3
    try std.testing.expectEqual(@as(u64, 0x00000000FF000000), w.double); // rank 4

    const k = generatePawnPushes(&b, .black);
    try std.testing.expectEqual(@as(u64, 0x0000FF0000000000), k.single); // rank 6
    try std.testing.expectEqual(@as(u64, 0x000000FF00000000), k.double); // rank 5
}

test "white pawn on e2 with a clear path" {
    const b = try fen.parseFen("4k3/8/8/8/8/8/4P3/4K3 w - - 0 1");
    const p = generatePawnPushes(&b, .white);
    try std.testing.expectEqual(squareBit(20), p.single); // e3
    try std.testing.expectEqual(squareBit(28), p.double); // e4
}

test "enemy piece directly in front blocks both pushes" {
    const b = try fen.parseFen("4k3/8/8/8/8/4p3/4P3/4K3 w - - 0 1");
    const p = generatePawnPushes(&b, .white);
    try std.testing.expectEqual(@as(u64, 0), p.single);
    try std.testing.expectEqual(@as(u64, 0), p.double);
}

test "own piece directly in front blocks both pushes" {
    const b = try fen.parseFen("4k3/8/8/8/8/4N3/4P3/4K3 w - - 0 1");
    const p = generatePawnPushes(&b, .white);
    try std.testing.expectEqual(@as(u64, 0), p.single);
    try std.testing.expectEqual(@as(u64, 0), p.double);
}

test "piece two squares ahead blocks only the double push" {
    const b = try fen.parseFen("4k3/8/8/8/4p3/8/4P3/4K3 w - - 0 1");
    const p = generatePawnPushes(&b, .white);
    try std.testing.expectEqual(squareBit(20), p.single); // e3
    try std.testing.expectEqual(@as(u64, 0), p.double);
}

test "pawn off its starting rank gets no double push" {
    const b = try fen.parseFen("4k3/8/8/8/8/4P3/8/4K3 w - - 0 1");
    const p = generatePawnPushes(&b, .white);
    try std.testing.expectEqual(squareBit(28), p.single); // e4
    try std.testing.expectEqual(@as(u64, 0), p.double);
}

test "one blocked pawn does not affect its neighbor" {
    // d2 is blocked by the black pawn on d3, e2 is free
    const b = try fen.parseFen("4k3/8/8/8/8/3p4/3PP3/4K3 w - - 0 1");
    const p = generatePawnPushes(&b, .white);
    try std.testing.expectEqual(squareBit(20), p.single); // e3
    try std.testing.expectEqual(squareBit(28), p.double); // e4
}

test "black pawn on e7 with a clear path" {
    const b = try fen.parseFen("4k3/4p3/8/8/8/8/8/4K3 b - - 0 1");
    const p = generatePawnPushes(&b, .black);
    try std.testing.expectEqual(squareBit(44), p.single); // e6
    try std.testing.expectEqual(squareBit(36), p.double); // e5
}

test "black pawn blocked by a white piece" {
    const b = try fen.parseFen("4k3/4p3/4P3/8/8/8/8/4K3 b - - 0 1");
    const p = generatePawnPushes(&b, .black);
    try std.testing.expectEqual(@as(u64, 0), p.single);
    try std.testing.expectEqual(@as(u64, 0), p.double);
}

test "pawn on the seventh rank pushes onto the last rank" {
    // Needed later for promotion: the push must land on e8 and shift nothing off the board.
    const b = try fen.parseFen("8/4P3/8/8/8/8/8/K6k w - - 0 1");
    const p = generatePawnPushes(&b, .white);
    try std.testing.expectEqual(squareBit(60), p.single); // e8
    try std.testing.expectEqual(@as(u64, 0), p.double);
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

test "starting position white pawn pushes produce 16 moves (8 single, 8 double) and no captures" {
    const b = try fen.parseFen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");
    const pushes = generatePawnPushes(&b, .white);

    var list = MoveList{};
    singlePawnPushesToMoves(pushes.single, .white, &list);
    try std.testing.expectEqual(@as(u16, 8), list.count);

    doublePawnPushesToMoves(pushes.double, .white, &list);
    try std.testing.expectEqual(@as(u16, 16), list.count);

    var single_count: usize = 0;
    var double_count: usize = 0;
    for (list.moves[0..list.count]) |m| {
        try std.testing.expect(!m.flags.isCapture());
        try std.testing.expect(!m.flags.isPromotion());
        if (m.flags == .quiet_move) {
            single_count += 1;
            try std.testing.expectEqual(m.from + 8, m.to);
        } else if (m.flags == .double_pawn_push) {
            double_count += 1;
            try std.testing.expectEqual(m.from + 16, m.to);
        } else {
            return error.TestUnexpectedResult;
        }
    }
    try std.testing.expectEqual(@as(usize, 8), single_count);
    try std.testing.expectEqual(@as(usize, 8), double_count);
}

test "starting position black pawn pushes produce 16 moves (8 single, 8 double) and no captures" {
    const b = try fen.parseFen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR b KQkq - 0 1");
    const pushes = generatePawnPushes(&b, .black);

    var list = MoveList{};
    singlePawnPushesToMoves(pushes.single, .black, &list);
    try std.testing.expectEqual(@as(u16, 8), list.count);

    doublePawnPushesToMoves(pushes.double, .black, &list);
    try std.testing.expectEqual(@as(u16, 16), list.count);

    var single_count: usize = 0;
    var double_count: usize = 0;
    for (list.moves[0..list.count]) |m| {
        try std.testing.expect(!m.flags.isCapture());
        try std.testing.expect(!m.flags.isPromotion());
        if (m.flags == .quiet_move) {
            single_count += 1;
            try std.testing.expectEqual(m.to + 8, m.from);
        } else if (m.flags == .double_pawn_push) {
            double_count += 1;
            try std.testing.expectEqual(m.to + 16, m.from);
        } else {
            return error.TestUnexpectedResult;
        }
    }
    try std.testing.expectEqual(@as(usize, 8), single_count);
    try std.testing.expectEqual(@as(usize, 8), double_count);
}

test "white pawn on e7 with e8 empty produces 4 distinct promotion moves" {
    const b = try fen.parseFen("8/4P3/8/8/8/8/8/K6k w - - 0 1");
    const pushes = generatePawnPushes(&b, .white);

    var list = MoveList{};
    singlePawnPushesToMoves(pushes.single, .white, &list);
    doublePawnPushesToMoves(pushes.double, .white, &list);

    try std.testing.expectEqual(@as(u16, 4), list.count);

    var seen: [6]bool = @splat(false);
    for (list.moves[0..list.count]) |m| {
        try std.testing.expectEqual(@as(brd.Square, 52), m.from); // e7
        try std.testing.expectEqual(@as(brd.Square, 60), m.to); // e8
        try std.testing.expect(m.flags.isPromotion());
        try std.testing.expect(!m.flags.isCapture());

        const promoted = m.flags.piecePromoted() orelse return error.TestUnexpectedResult;
        seen[@backingInt(promoted)] = true;
    }

    try std.testing.expect(seen[@backingInt(Piece.knight)]);
    try std.testing.expect(seen[@backingInt(Piece.bishop)]);
    try std.testing.expect(seen[@backingInt(Piece.rook)]);
    try std.testing.expect(seen[@backingInt(Piece.queen)]);
}

test "black pawn on e2 with e1 empty produces 4 distinct promotion moves" {
    const b = try fen.parseFen("K6k/8/8/8/8/8/4p3/8 b - - 0 1");
    const pushes = generatePawnPushes(&b, .black);

    var list = MoveList{};
    singlePawnPushesToMoves(pushes.single, .black, &list);
    doublePawnPushesToMoves(pushes.double, .black, &list);

    try std.testing.expectEqual(@as(u16, 4), list.count);

    var seen: [6]bool = @splat(false);
    for (list.moves[0..list.count]) |m| {
        try std.testing.expectEqual(@as(brd.Square, 12), m.from); // e2
        try std.testing.expectEqual(@as(brd.Square, 4), m.to); // e1
        try std.testing.expect(m.flags.isPromotion());
        try std.testing.expect(!m.flags.isCapture());

        const promoted = m.flags.piecePromoted() orelse return error.TestUnexpectedResult;
        seen[@backingInt(promoted)] = true;
    }

    try std.testing.expect(seen[@backingInt(Piece.knight)]);
    try std.testing.expect(seen[@backingInt(Piece.bishop)]);
    try std.testing.expect(seen[@backingInt(Piece.rook)]);
    try std.testing.expect(seen[@backingInt(Piece.queen)]);
}

test "double push move carries double_pawn_push flag and expected squares" {
    // White e2 (12) -> e4 (28)
    const bw = try fen.parseFen("4k3/8/8/8/8/8/4P3/4K3 w - - 0 1");
    const pw = generatePawnPushes(&bw, .white);
    var white_list = MoveList{};
    doublePawnPushesToMoves(pw.double, .white, &white_list);

    try std.testing.expectEqual(@as(u16, 1), white_list.count);
    try std.testing.expectEqual(@as(brd.Square, 12), white_list.moves[0].from);
    try std.testing.expectEqual(@as(brd.Square, 28), white_list.moves[0].to);
    try std.testing.expectEqual(MoveFlags.double_pawn_push, white_list.moves[0].flags);

    // Black e7 (52) -> e5 (36)
    const bb = try fen.parseFen("4k3/4p3/8/8/8/8/8/4K3 b - - 0 1");
    const pb = generatePawnPushes(&bb, .black);
    var black_list = MoveList{};
    doublePawnPushesToMoves(pb.double, .black, &black_list);

    try std.testing.expectEqual(@as(u16, 1), black_list.count);
    try std.testing.expectEqual(@as(brd.Square, 52), black_list.moves[0].from);
    try std.testing.expectEqual(@as(brd.Square, 36), black_list.moves[0].to);
    try std.testing.expectEqual(MoveFlags.double_pawn_push, black_list.moves[0].flags);
}

test "mixed quiet pushes and promotions on the same board" {
    // White pawn on a2 (8) and e7 (52)
    const b = try fen.parseFen("8/4P3/8/8/8/8/P7/K6k w - - 0 1");
    const pushes = generatePawnPushes(&b, .white);

    var list = MoveList{};
    singlePawnPushesToMoves(pushes.single, .white, &list);
    doublePawnPushesToMoves(pushes.double, .white, &list);

    // a2->a3 (1 quiet) + e7->e8 (4 promotions) + a2->a4 (1 double push) = 6 moves
    try std.testing.expectEqual(@as(u16, 6), list.count);
    try std.testing.expectEqual(Move{ .from = 8, .to = 16, .flags = .quiet_move }, list.moves[0]);
    try std.testing.expectEqual(Move{ .from = 8, .to = 24, .flags = .double_pawn_push }, list.moves[5]);
}

test "empty bitboard adds no pawn push moves" {
    var list = MoveList{};
    singlePawnPushesToMoves(0, .white, &list);
    doublePawnPushesToMoves(0, .white, &list);
    singlePawnPushesToMoves(0, .black, &list);
    doublePawnPushesToMoves(0, .black, &list);
    try std.testing.expectEqual(@as(u16, 0), list.count);
}
