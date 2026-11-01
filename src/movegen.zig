const std = @import("std");
const fen = @import("fen.zig");
const brd = @import("board.zig");
const att = @import("attacks.zig");

const Board = brd.Board;
const Color = brd.Color;
const Piece = brd.Piece;

const rank_1: u64 = 0x00000000000000FF; // black promotion rank
const rank_3: u64 = 0x0000000000FF0000; // where a white pawn lands after a push from rank 2 (double-push filter); black's en passant target rank
const rank_6: u64 = 0x0000FF0000000000; // where a black pawn lands after a push from rank 7 (double-push filter); white's en passant target rank
const rank_8: u64 = 0xFF00000000000000; // white promotion rank
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
fn addPromotionMoves(move_list: *MoveList, from: brd.Square, to: brd.Square, is_capture: bool) void {
    const flags = if (is_capture) capture_promotion_flags else quiet_promotion_flags;
    for (flags) |flag| {
        move_list.add(.{
            .from = from,
            .to = to,
            .flags = flag,
        });
    }
}

pub fn singlePawnPushesToMoves(bit_board: u64, color: Color, move_list: *MoveList) void {
    // Split destinations up front by promotion rank so the inner loops need no per-square rank checks.
    const promotion_rank = if (color == .white) rank_8 else rank_1;
    var normal = bit_board & ~promotion_rank;
    var promoting = bit_board & promotion_rank;

    while (normal != 0) : (normal &= normal - 1) {
        const to: brd.Square = @intCast(@ctz(normal));
        move_list.add(.{
            .from = if (color == .white) to - 8 else to + 8,
            .to = to,
            .flags = .quiet_move,
        });
    }

    while (promoting != 0) : (promoting &= promoting - 1) {
        const to: brd.Square = @intCast(@ctz(promoting));
        const from: brd.Square = if (color == .white) to - 8 else to + 8;
        addPromotionMoves(move_list, from, to, false);
    }
}

pub fn doublePawnPushesToMoves(bit_board: u64, color: Color, move_list: *MoveList) void {
    // Double pushes only land on rank 4 (white) or rank 5 (black), so they never promote
    // and only differ in the direction of the 16-square offset.
    var bb = bit_board;
    while (bb != 0) : (bb &= bb - 1) {
        const to: brd.Square = @intCast(@ctz(bb));
        move_list.add(.{
            .from = if (color == .white) to - 16 else to + 16,
            .to = to,
            .flags = .double_pawn_push,
        });
    }
}

pub fn pawnCapturesToMoves(board: *const Board, color: Color, move_list: *MoveList) void {
    var pawns = board.getBoard(color, .pawn);
    const occupied_by_opponent = board.occupancy[@backingInt(color.opposite())]; // pawn captures only legal if occupied by opponent or en passant
    const promotion_rank = if (color == .white) rank_8 else rank_1;
    const ep_rank = if (color == .white) rank_6 else rank_3;

    while (pawns != 0) : (pawns &= pawns - 1) {
        const pawn_square: brd.Square = @intCast(@ctz(pawns));
        const pawn_attacks = att.pawn_attacks[@backingInt(color)][pawn_square];

        // Check if attacking the en passant target square on the opponent's en passant rank.
        if (board.en_passant) |ep_sq| {
            if (pawn_attacks & squareBit(ep_sq) & ep_rank != 0) {
                move_list.add(.{
                    .from = pawn_square,
                    .to = ep_sq,
                    .flags = .en_passant_capture,
                });
            }
        }

        // Partition attacked opponent squares into normal captures and promotion captures.
        const opponents_attacked = pawn_attacks & occupied_by_opponent;
        var normal = opponents_attacked & ~promotion_rank;
        var promoting = opponents_attacked & promotion_rank;

        while (normal != 0) : (normal &= normal - 1) {
            const attack_square: brd.Square = @intCast(@ctz(normal));
            move_list.add(.{
                .from = pawn_square,
                .to = attack_square,
                .flags = .capture,
            });
        }

        while (promoting != 0) : (promoting &= promoting - 1) {
            const attack_square: brd.Square = @intCast(@ctz(promoting));
            addPromotionMoves(move_list, pawn_square, attack_square, true);
        }
    }
}

pub fn leaperMoves(board: *const Board, color: Color, piece: Piece, move_list: *MoveList) void {
    var bb = board.getBoard(color, piece);
    const attack_table = switch (piece) {
        .knight => att.knight_attacks,
        .king => att.king_attacks,
        else => @panic("got non leaper in leaperMoves"),
    };
    const own_occupancy = board.occupancy[@backingInt(color)];
    const opponent_occupancy = board.occupancy[@backingInt(color.opposite())];

    while (bb != 0) : (bb &= bb - 1) {
        const sq: brd.Square = @intCast(@ctz(bb));
        const attacked_squares = attack_table[sq] & ~own_occupancy;

        var captures = attacked_squares & opponent_occupancy;
        var quiet_moves = attacked_squares & ~opponent_occupancy;

        while (quiet_moves != 0) : (quiet_moves &= quiet_moves - 1) {
            const attack_square: brd.Square = @intCast(@ctz(quiet_moves));
            move_list.add(.{
                .from = sq,
                .to = attack_square,
                .flags = .quiet_move,
            });
        }

        while (captures != 0) : (captures &= captures - 1) {
            const attack_square: brd.Square = @intCast(@ctz(captures));
            move_list.add(.{
                .from = sq,
                .to = attack_square,
                .flags = .capture,
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

test "starting position has no pawn captures for either side" {
    const b = try fen.parseFen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");
    var list = MoveList{};

    pawnCapturesToMoves(&b, .white, &list);
    try std.testing.expectEqual(@as(u16, 0), list.count);

    pawnCapturesToMoves(&b, .black, &list);
    try std.testing.expectEqual(@as(u16, 0), list.count);
}

test "white pawn captures enemy pieces on both diagonals" {
    // White pawn on e4 (28), black pawns on d5 (35) and f5 (37)
    const b = try fen.parseFen("4k3/8/8/3p1p2/4P3/8/8/4K3 w - - 0 1");
    var list = MoveList{};
    pawnCapturesToMoves(&b, .white, &list);

    try std.testing.expectEqual(@as(u16, 2), list.count);
    try std.testing.expectEqual(Move{ .from = 28, .to = 35, .flags = .capture }, list.moves[0]);
    try std.testing.expectEqual(Move{ .from = 28, .to = 37, .flags = .capture }, list.moves[1]);
}

test "black pawn captures enemy pieces on both diagonals" {
    // Black pawn on e5 (36), white pawns on d4 (27) and f4 (29)
    const b = try fen.parseFen("4k3/8/8/4p3/3P1P2/8/8/4K3 b - - 0 1");
    var list = MoveList{};
    pawnCapturesToMoves(&b, .black, &list);

    try std.testing.expectEqual(@as(u16, 2), list.count);
    try std.testing.expectEqual(Move{ .from = 36, .to = 27, .flags = .capture }, list.moves[0]);
    try std.testing.expectEqual(Move{ .from = 36, .to = 29, .flags = .capture }, list.moves[1]);
}

test "pawns cannot capture friendly pieces" {
    // White pawn on e4 (28) with white knights on d5 (35) and f5 (37)
    const b = try fen.parseFen("4k3/8/8/3N1N2/4P3/8/8/4K3 w - - 0 1");
    var list = MoveList{};
    pawnCapturesToMoves(&b, .white, &list);

    try std.testing.expectEqual(@as(u16, 0), list.count);
}

test "edge-file pawn captures do not wrap around the board" {
    // White pawns on a4 (24) and h4 (31), black pawns on b5 (33), g5 (38), a5 (32), h5 (39)
    const b = try fen.parseFen("4k3/8/8/pp4pp/P6P/8/8/4K3 w - - 0 1");
    var list = MoveList{};
    pawnCapturesToMoves(&b, .white, &list);

    // a4 only captures b5 (24 -> 33); h4 only captures g5 (31 -> 38)
    try std.testing.expectEqual(@as(u16, 2), list.count);
    try std.testing.expectEqual(Move{ .from = 24, .to = 33, .flags = .capture }, list.moves[0]);
    try std.testing.expectEqual(Move{ .from = 31, .to = 38, .flags = .capture }, list.moves[1]);
}

test "white pawn capture onto the eighth rank produces 4 capture-promotion moves" {
    // White pawn on e7 (52), black rook on d8 (59)
    const b = try fen.parseFen("3r3k/4P3/8/8/8/8/8/4K3 w - - 0 1");
    var list = MoveList{};
    pawnCapturesToMoves(&b, .white, &list);

    try std.testing.expectEqual(@as(u16, 4), list.count);

    var seen: [6]bool = @splat(false);
    for (list.moves[0..list.count]) |m| {
        try std.testing.expectEqual(@as(brd.Square, 52), m.from); // e7
        try std.testing.expectEqual(@as(brd.Square, 59), m.to); // d8
        try std.testing.expect(m.flags.isCapture());
        try std.testing.expect(m.flags.isPromotion());

        const promoted = m.flags.piecePromoted() orelse return error.TestUnexpectedResult;
        seen[@backingInt(promoted)] = true;
    }

    try std.testing.expect(seen[@backingInt(Piece.knight)]);
    try std.testing.expect(seen[@backingInt(Piece.bishop)]);
    try std.testing.expect(seen[@backingInt(Piece.rook)]);
    try std.testing.expect(seen[@backingInt(Piece.queen)]);
}

test "black pawn capture onto the first rank produces 4 capture-promotion moves" {
    // Black pawn on e2 (12), white rook on f1 (5)
    const b = try fen.parseFen("4k3/8/8/8/8/8/4p3/K4R2 b - - 0 1");
    var list = MoveList{};
    pawnCapturesToMoves(&b, .black, &list);

    try std.testing.expectEqual(@as(u16, 4), list.count);

    var seen: [6]bool = @splat(false);
    for (list.moves[0..list.count]) |m| {
        try std.testing.expectEqual(@as(brd.Square, 12), m.from); // e2
        try std.testing.expectEqual(@as(brd.Square, 5), m.to); // f1
        try std.testing.expect(m.flags.isCapture());
        try std.testing.expect(m.flags.isPromotion());

        const promoted = m.flags.piecePromoted() orelse return error.TestUnexpectedResult;
        seen[@backingInt(promoted)] = true;
    }

    try std.testing.expect(seen[@backingInt(Piece.knight)]);
    try std.testing.expect(seen[@backingInt(Piece.bishop)]);
    try std.testing.expect(seen[@backingInt(Piece.rook)]);
    try std.testing.expect(seen[@backingInt(Piece.queen)]);
}

test "white en passant capture produces en_passant_capture move" {
    // White pawn on e5 (36), black pawn just played d7-d5 so en passant target is d6 (43)
    const b = try fen.parseFen("4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1");
    var list = MoveList{};
    pawnCapturesToMoves(&b, .white, &list);

    try std.testing.expectEqual(@as(u16, 1), list.count);
    try std.testing.expectEqual(Move{
        .from = 36,
        .to = 43,
        .flags = .en_passant_capture,
    }, list.moves[0]);
    try std.testing.expect(list.moves[0].flags.isCapture());
    try std.testing.expect(!list.moves[0].flags.isPromotion());
}

test "black en passant capture produces en_passant_capture move" {
    // Black pawn on d4 (27), white pawn just played e2-e4 so en passant target is e3 (20)
    const b = try fen.parseFen("4k3/8/8/8/3pP3/8/8/4K3 b - e3 0 1");
    var list = MoveList{};
    pawnCapturesToMoves(&b, .black, &list);

    try std.testing.expectEqual(@as(u16, 1), list.count);
    try std.testing.expectEqual(Move{
        .from = 27,
        .to = 20,
        .flags = .en_passant_capture,
    }, list.moves[0]);
    try std.testing.expect(list.moves[0].flags.isCapture());
    try std.testing.expect(!list.moves[0].flags.isPromotion());
}

test "two pawns able to capture the same en passant square" {
    // White pawns on d5 (35) and f5 (37), en passant target on e6 (44)
    const b = try fen.parseFen("4k3/8/8/3PpP2/8/8/8/4K3 w - e6 0 1");
    var list = MoveList{};
    pawnCapturesToMoves(&b, .white, &list);

    try std.testing.expectEqual(@as(u16, 2), list.count);
    try std.testing.expectEqual(Move{ .from = 35, .to = 44, .flags = .en_passant_capture }, list.moves[0]);
    try std.testing.expectEqual(Move{ .from = 37, .to = 44, .flags = .en_passant_capture }, list.moves[1]);
}

test "cannot en passant capture own side" {
    // White double-pushed e2-e4 setting ep = e3 (20, rank 3).
    // Friendly white pawns on d2 (11) and f2 (13) attack e3, but must not en-passant their own pawn.
    const white_ep_board = try fen.parseFen("4k3/8/8/8/4P3/8/3P1P2/4K3 w - e3 0 1");
    var white_list = MoveList{};
    pawnCapturesToMoves(&white_ep_board, .white, &white_list);
    try std.testing.expectEqual(@as(u16, 0), white_list.count);

    // Black double-pushed e7-e5 setting ep = e6 (44, rank 6).
    // Friendly black pawns on d7 (51) and f7 (53) attack e6, but must not en-passant their own pawn.
    const black_ep_board = try fen.parseFen("4k3/3p1p2/8/4p3/8/8/8/4K3 b - e6 0 1");
    var black_list = MoveList{};
    pawnCapturesToMoves(&black_ep_board, .black, &black_list);
    try std.testing.expectEqual(@as(u16, 0), black_list.count);
}

test "en passant square out of reach produces no en passant move" {
    // White pawn on a5 (32), en passant square is e6 (44)
    const b = try fen.parseFen("4k3/8/8/P3p3/8/8/8/4K3 w - e6 0 1");
    var list = MoveList{};
    pawnCapturesToMoves(&b, .white, &list);

    try std.testing.expectEqual(@as(u16, 0), list.count);
}

test "en passant does not wrap across files" {
    // White pawn on h4 (31), black pawn on a5 (32).
    // Without file masking, h4 would wrap to a6 (40) and a5 would wrap to h3 (23).
    const bw = try fen.parseFen("4k3/8/8/p7/7P/8/8/4K3 w - a6 0 1");
    var white_list = MoveList{};
    pawnCapturesToMoves(&bw, .white, &white_list);
    try std.testing.expectEqual(@as(u16, 0), white_list.count);

    const bb = try fen.parseFen("4k3/8/8/p7/7P/8/8/4K3 b - h3 0 1");
    var black_list = MoveList{};
    pawnCapturesToMoves(&bb, .black, &black_list);
    try std.testing.expectEqual(@as(u16, 0), black_list.count);
}

test "knight on e4 in an empty board produces 8 quiet moves" {
    const b = try fen.parseFen("8/8/8/8/4N3/8/8/8 w - - 0 1");
    var list = MoveList{};
    leaperMoves(&b, .white, .knight, &list);

    try std.testing.expectEqual(@as(u16, 8), list.count);
    for (list.moves[0..list.count]) |m| {
        try std.testing.expectEqual(@as(brd.Square, 28), m.from);
        try std.testing.expectEqual(MoveFlags.quiet_move, m.flags);
    }
}

test "knight on e4 with a friendly piece on one target produces 7 quiet moves" {
    // White knight on e4 (28), friendly pawn on d6 (43)
    const b = try fen.parseFen("8/8/3P4/8/4N3/8/8/8 w - - 0 1");
    var list = MoveList{};
    leaperMoves(&b, .white, .knight, &list);

    try std.testing.expectEqual(@as(u16, 7), list.count);
    for (list.moves[0..list.count]) |m| {
        try std.testing.expectEqual(@as(brd.Square, 28), m.from);
        try std.testing.expectEqual(MoveFlags.quiet_move, m.flags);
        try std.testing.expect(m.to != 43);
    }
}

test "knight on e4 with an enemy piece on one target produces 7 quiet moves and 1 capture" {
    // White knight on e4 (28), black pawn on d6 (43)
    const b = try fen.parseFen("8/8/3p4/8/4N3/8/8/8 w - - 0 1");
    var list = MoveList{};
    leaperMoves(&b, .white, .knight, &list);

    try std.testing.expectEqual(@as(u16, 8), list.count);

    var quiet_count: usize = 0;
    var capture_count: usize = 0;
    for (list.moves[0..list.count]) |m| {
        try std.testing.expectEqual(@as(brd.Square, 28), m.from);
        if (m.flags == .quiet_move) {
            quiet_count += 1;
            try std.testing.expect(m.to != 43);
        } else if (m.flags == .capture) {
            capture_count += 1;
            try std.testing.expectEqual(@as(brd.Square, 43), m.to);
        } else {
            return error.TestUnexpectedResult;
        }
    }
    try std.testing.expectEqual(@as(usize, 7), quiet_count);
    try std.testing.expectEqual(@as(usize, 1), capture_count);
}

test "knight on a1 produces 2 moves" {
    const b = try fen.parseFen("8/8/8/8/8/8/8/N7 w - - 0 1");
    var list = MoveList{};
    leaperMoves(&b, .white, .knight, &list);

    try std.testing.expectEqual(@as(u16, 2), list.count);
    // a1 (0) -> c2 (10), b3 (17)
    try std.testing.expectEqual(Move{ .from = 0, .to = 10, .flags = .quiet_move }, list.moves[0]);
    try std.testing.expectEqual(Move{ .from = 0, .to = 17, .flags = .quiet_move }, list.moves[1]);
}

test "king on e4 produces 8 moves and king on a1 produces 3" {
    const b_center = try fen.parseFen("8/8/8/8/4K3/8/8/8 w - - 0 1");
    var center_list = MoveList{};
    leaperMoves(&b_center, .white, .king, &center_list);

    try std.testing.expectEqual(@as(u16, 8), center_list.count);
    for (center_list.moves[0..center_list.count]) |m| {
        try std.testing.expectEqual(@as(brd.Square, 28), m.from);
        try std.testing.expectEqual(MoveFlags.quiet_move, m.flags);
    }

    const b_corner = try fen.parseFen("8/8/8/8/8/8/8/K7 w - - 0 1");
    var corner_list = MoveList{};
    leaperMoves(&b_corner, .white, .king, &corner_list);

    try std.testing.expectEqual(@as(u16, 3), corner_list.count);
    // a1 (0) -> b1 (1), a2 (8), b2 (9)
    try std.testing.expectEqual(Move{ .from = 0, .to = 1, .flags = .quiet_move }, corner_list.moves[0]);
    try std.testing.expectEqual(Move{ .from = 0, .to = 8, .flags = .quiet_move }, corner_list.moves[1]);
    try std.testing.expectEqual(Move{ .from = 0, .to = 9, .flags = .quiet_move }, corner_list.moves[2]);
}

test "starting position leaper moves: 4 knight moves and 0 king moves for both sides" {
    const b = try fen.parseFen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");

    // White: 4 knight moves (b1->a3, b1->c3, g1->f3, g1->h3) and 0 king moves
    var white_king_list = MoveList{};
    leaperMoves(&b, .white, .king, &white_king_list);
    try std.testing.expectEqual(@as(u16, 0), white_king_list.count);

    var white_list = MoveList{};
    leaperMoves(&b, .white, .knight, &white_list);
    leaperMoves(&b, .white, .king, &white_list);
    try std.testing.expectEqual(@as(u16, 4), white_list.count);
    try std.testing.expectEqual(Move{ .from = 1, .to = 16, .flags = .quiet_move }, white_list.moves[0]);
    try std.testing.expectEqual(Move{ .from = 1, .to = 18, .flags = .quiet_move }, white_list.moves[1]);
    try std.testing.expectEqual(Move{ .from = 6, .to = 21, .flags = .quiet_move }, white_list.moves[2]);
    try std.testing.expectEqual(Move{ .from = 6, .to = 23, .flags = .quiet_move }, white_list.moves[3]);

    // Black: 4 knight moves (b8->a6, b8->c6, g8->f6, g8->h6) and 0 king moves
    var black_list = MoveList{};
    leaperMoves(&b, .black, .knight, &black_list);
    leaperMoves(&b, .black, .king, &black_list);
    try std.testing.expectEqual(@as(u16, 4), black_list.count);
    try std.testing.expectEqual(Move{ .from = 57, .to = 40, .flags = .quiet_move }, black_list.moves[0]);
    try std.testing.expectEqual(Move{ .from = 57, .to = 42, .flags = .quiet_move }, black_list.moves[1]);
    try std.testing.expectEqual(Move{ .from = 62, .to = 45, .flags = .quiet_move }, black_list.moves[2]);
    try std.testing.expectEqual(Move{ .from = 62, .to = 47, .flags = .quiet_move }, black_list.moves[3]);
}

test "king captures enemy piece and is blocked by friendly piece" {
    // White king on e4 (28), friendly pawn on e5 (36), black pawn on d5 (35)
    const b = try fen.parseFen("8/8/8/3pP3/4K3/8/8/8 w - - 0 1");
    var list = MoveList{};
    leaperMoves(&b, .white, .king, &list);

    try std.testing.expectEqual(@as(u16, 7), list.count);

    var quiet_count: usize = 0;
    var capture_count: usize = 0;
    for (list.moves[0..list.count]) |m| {
        try std.testing.expectEqual(@as(brd.Square, 28), m.from);
        try std.testing.expect(m.to != 36); // blocked by own pawn on e5
        if (m.flags == .quiet_move) {
            quiet_count += 1;
        } else if (m.flags == .capture) {
            capture_count += 1;
            try std.testing.expectEqual(@as(brd.Square, 35), m.to);
        } else {
            return error.TestUnexpectedResult;
        }
    }
    try std.testing.expectEqual(@as(usize, 6), quiet_count);
    try std.testing.expectEqual(@as(usize, 1), capture_count);
}
