const std = @import("std");
const fen = @import("fen.zig");
const brd = @import("board.zig");
const att = @import("attacks.zig");

const Board = brd.Board;
const Color = brd.Color;
const Piece = brd.Piece;

const squareBit = brd.squareBit;

const rank_1: u64 = 0x00000000000000FF; // black promotion rank
const rank_3: u64 = 0x0000000000FF0000; // where a white pawn lands after a push from rank 2 (double-push filter); black's en passant target rank
const rank_6: u64 = 0x0000FF0000000000; // where a black pawn lands after a push from rank 7 (double-push filter); white's en passant target rank
const rank_8: u64 = 0xFF00000000000000; // white promotion rank

/// Pass in 0-7 for rank and file
pub fn bitBoardFromRankAndFile(rank: u3, file: u3) u64 {
    return squareBit(@as(u6, rank) * 8 + file);
}

pub const RayDirection = enum(u3) {
    north = 0,
    northeast = 1,
    northwest = 2,
    east = 3,
    south = 4,
    southeast = 5,
    southwest = 6,
    west = 7,
};

pub const ray_table: [8][64]u64 = blk: {
    @setEvalBranchQuota(10000);
    var rays: [8][64]u64 = @splat(@splat(0));

    // Step vectors (rank_step, file_step) ordered to match RayDirection enum values.
    const steps = [8][2]i8{
        .{ 1, 0 }, // north
        .{ 1, 1 }, // northeast
        .{ 1, -1 }, // northwest
        .{ 0, 1 }, // east
        .{ -1, 0 }, // south
        .{ -1, 1 }, // southeast
        .{ -1, -1 }, // southwest
        .{ 0, -1 }, // west
    };

    for (steps, 0..) |step, dir| {
        const rank_step = step[0];
        const file_step = step[1];

        for (0..64) |sq| {
            var rank: i8 = @intCast(sq / 8);
            var file: i8 = @intCast(sq % 8);
            rank += rank_step;
            file += file_step;
            while (rank >= 0 and rank < 8 and file >= 0 and file < 8) : ({
                rank += rank_step;
                file += file_step;
            }) {
                rays[dir][sq] |= bitBoardFromRankAndFile(@intCast(rank), @intCast(file));
            }
        }
    }

    break :blk rays;
};

pub fn rayAttacks(comptime direction: RayDirection, from: brd.Square, occupancy: u64) u64 {
    const dir = @backingInt(direction);
    const blockers = ray_table[dir][from] & occupancy;

    if (blockers == 0) return ray_table[dir][from]; // if no blocker, return whole ray, preventing overflow on the following @intCast and preventing underflow in following 63 - @clz

    const first_blocker: brd.Square = if (dir < 4) @intCast(@ctz(blockers)) else @intCast(63 - @clz(blockers)); // use @ctz to get the first blocker when going 'up' the bitboard; when going down, use @clz
    return ray_table[dir][from] ^ ray_table[dir][first_blocker];
}

pub fn rookAttacks(from: brd.Square, occupancy: u64) u64 {
    return rayAttacks(.north, from, occupancy) | rayAttacks(.east, from, occupancy) | rayAttacks(.west, from, occupancy) | rayAttacks(.south, from, occupancy);
}

pub fn bishopAttacks(from: brd.Square, occupancy: u64) u64 {
    return rayAttacks(.northeast, from, occupancy) | rayAttacks(.northwest, from, occupancy) | rayAttacks(.southeast, from, occupancy) | rayAttacks(.southwest, from, occupancy);
}

pub fn queenAttacks(from: brd.Square, occupancy: u64) u64 {
    return bishopAttacks(from, occupancy) | rookAttacks(from, occupancy);
}

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

pub fn leaperMoves(board: *const Board, color: Color, comptime piece: Piece, move_list: *MoveList) void {
    var bb = board.getBoard(color, piece);
    const attack_table = switch (piece) {
        .knight => &att.knight_attacks,
        .king => &att.king_attacks,
        else => @compileError("leaperMoves needs a knight or king"),
    };
    const own_occupancy = board.occupancy[@backingInt(color)];
    const opponent_occupancy = board.occupancy[@backingInt(color.opposite())];

    while (bb != 0) : (bb &= bb - 1) {
        const sq: brd.Square = @intCast(@ctz(bb));
        const targets = attack_table[sq] & ~own_occupancy;

        addMovesFromTargets(move_list, sq, targets, opponent_occupancy);
    }
}

pub fn sliderMoves(board: *const Board, color: Color, comptime piece: Piece, move_list: *MoveList) void {
    var bb = board.getBoard(color, piece);

    const own_occupancy = board.occupancy[@backingInt(color)];
    const opponent_occupancy = board.occupancy[@backingInt(color.opposite())];

    while (bb != 0) : (bb &= bb - 1) {
        const sq: brd.Square = @intCast(@ctz(bb));
        const targets = switch (piece) {
            .bishop => bishopAttacks(sq, opponent_occupancy | own_occupancy),
            .rook => rookAttacks(sq, opponent_occupancy | own_occupancy),
            .queen => queenAttacks(sq, opponent_occupancy | own_occupancy),
            else => @compileError("sliderMoves needs a bishop, rook, or queen"),
        } & ~own_occupancy;

        addMovesFromTargets(move_list, sq, targets, opponent_occupancy);
    }
}

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

test "ray_table from corners a1 and h8" {
    // a1 (0): North = a2..a8, East = b1..h1, Northeast = b2..h8, all others empty
    const a1_north = squareBit(8) | squareBit(16) | squareBit(24) | squareBit(32) | squareBit(40) | squareBit(48) | squareBit(56);
    const a1_east = squareBit(1) | squareBit(2) | squareBit(3) | squareBit(4) | squareBit(5) | squareBit(6) | squareBit(7);
    const a1_ne = squareBit(9) | squareBit(18) | squareBit(27) | squareBit(36) | squareBit(45) | squareBit(54) | squareBit(63);

    try std.testing.expectEqual(a1_north, ray_table[@backingInt(RayDirection.north)][0]);
    try std.testing.expectEqual(a1_east, ray_table[@backingInt(RayDirection.east)][0]);
    try std.testing.expectEqual(a1_ne, ray_table[@backingInt(RayDirection.northeast)][0]);
    try std.testing.expectEqual(@as(u64, 0), ray_table[@backingInt(RayDirection.northwest)][0]);
    try std.testing.expectEqual(@as(u64, 0), ray_table[@backingInt(RayDirection.south)][0]);
    try std.testing.expectEqual(@as(u64, 0), ray_table[@backingInt(RayDirection.southeast)][0]);
    try std.testing.expectEqual(@as(u64, 0), ray_table[@backingInt(RayDirection.southwest)][0]);
    try std.testing.expectEqual(@as(u64, 0), ray_table[@backingInt(RayDirection.west)][0]);

    // h8 (63): South = h1..h7, West = a8..g8, Southwest = a1..g7, all others empty
    const h8_south = squareBit(7) | squareBit(15) | squareBit(23) | squareBit(31) | squareBit(39) | squareBit(47) | squareBit(55);
    const h8_west = squareBit(56) | squareBit(57) | squareBit(58) | squareBit(59) | squareBit(60) | squareBit(61) | squareBit(62);
    const h8_sw = squareBit(0) | squareBit(9) | squareBit(18) | squareBit(27) | squareBit(36) | squareBit(45) | squareBit(54);

    try std.testing.expectEqual(h8_south, ray_table[@backingInt(RayDirection.south)][63]);
    try std.testing.expectEqual(h8_west, ray_table[@backingInt(RayDirection.west)][63]);
    try std.testing.expectEqual(h8_sw, ray_table[@backingInt(RayDirection.southwest)][63]);
    try std.testing.expectEqual(@as(u64, 0), ray_table[@backingInt(RayDirection.north)][63]);
    try std.testing.expectEqual(@as(u64, 0), ray_table[@backingInt(RayDirection.northeast)][63]);
    try std.testing.expectEqual(@as(u64, 0), ray_table[@backingInt(RayDirection.northwest)][63]);
    try std.testing.expectEqual(@as(u64, 0), ray_table[@backingInt(RayDirection.east)][63]);
    try std.testing.expectEqual(@as(u64, 0), ray_table[@backingInt(RayDirection.southeast)][63]);
}

test "ray_table from center square e4 in all 8 directions" {
    // e4 = 28 (rank 3, file 4)
    try std.testing.expectEqual(
        squareBit(36) | squareBit(44) | squareBit(52) | squareBit(60), // e5, e6, e7, e8
        ray_table[@backingInt(RayDirection.north)][28],
    );
    try std.testing.expectEqual(
        squareBit(20) | squareBit(12) | squareBit(4), // e3, e2, e1
        ray_table[@backingInt(RayDirection.south)][28],
    );
    try std.testing.expectEqual(
        squareBit(29) | squareBit(30) | squareBit(31), // f4, g4, h4
        ray_table[@backingInt(RayDirection.east)][28],
    );
    try std.testing.expectEqual(
        squareBit(27) | squareBit(26) | squareBit(25) | squareBit(24), // d4, c4, b4, a4
        ray_table[@backingInt(RayDirection.west)][28],
    );
    try std.testing.expectEqual(
        squareBit(37) | squareBit(46) | squareBit(55), // f5, g6, h7
        ray_table[@backingInt(RayDirection.northeast)][28],
    );
    try std.testing.expectEqual(
        squareBit(35) | squareBit(42) | squareBit(49) | squareBit(56), // d5, c6, b7, a8
        ray_table[@backingInt(RayDirection.northwest)][28],
    );
    try std.testing.expectEqual(
        squareBit(21) | squareBit(14) | squareBit(7), // f3, g2, h1
        ray_table[@backingInt(RayDirection.southeast)][28],
    );
    try std.testing.expectEqual(
        squareBit(19) | squareBit(10) | squareBit(1), // d3, c2, b1
        ray_table[@backingInt(RayDirection.southwest)][28],
    );
}

test "ray_table has no self-inclusion, disjoint directions, and 14 rook squares per square" {
    for (0..64) |sq| {
        const origin_bit = squareBit(@intCast(sq));

        for (0..8) |d1| {
            // A ray never includes the origin square itself
            try std.testing.expectEqual(@as(u64, 0), ray_table[d1][sq] & origin_bit);

            // Different directions from the same square never overlap
            for ((d1 + 1)..8) |d2| {
                try std.testing.expectEqual(@as(u64, 0), ray_table[d1][sq] & ray_table[d2][sq]);
            }
        }

        // Orthogonal rays from any square always cover 7 rank + 7 file = 14 squares
        const rook_rays = ray_table[@backingInt(RayDirection.north)][sq] |
            ray_table[@backingInt(RayDirection.south)][sq] |
            ray_table[@backingInt(RayDirection.east)][sq] |
            ray_table[@backingInt(RayDirection.west)][sq];
        try std.testing.expectEqual(@as(u7, 14), @popCount(rook_rays));
    }
}

test "ray_table rook and bishop square counts on d4 and a1" {
    // d4 = 27: rook attacks 14 squares, bishop attacks 13 squares
    const d4_rook = ray_table[@backingInt(RayDirection.north)][27] |
        ray_table[@backingInt(RayDirection.south)][27] |
        ray_table[@backingInt(RayDirection.east)][27] |
        ray_table[@backingInt(RayDirection.west)][27];
    const d4_bishop = ray_table[@backingInt(RayDirection.northeast)][27] |
        ray_table[@backingInt(RayDirection.northwest)][27] |
        ray_table[@backingInt(RayDirection.southeast)][27] |
        ray_table[@backingInt(RayDirection.southwest)][27];
    try std.testing.expectEqual(@as(u7, 14), @popCount(d4_rook));
    try std.testing.expectEqual(@as(u7, 13), @popCount(d4_bishop));

    // a1 = 0: rook attacks 14 squares, bishop attacks 7 squares
    const a1_rook = ray_table[@backingInt(RayDirection.north)][0] |
        ray_table[@backingInt(RayDirection.south)][0] |
        ray_table[@backingInt(RayDirection.east)][0] |
        ray_table[@backingInt(RayDirection.west)][0];
    const a1_bishop = ray_table[@backingInt(RayDirection.northeast)][0] |
        ray_table[@backingInt(RayDirection.northwest)][0] |
        ray_table[@backingInt(RayDirection.southeast)][0] |
        ray_table[@backingInt(RayDirection.southwest)][0];
    try std.testing.expectEqual(@as(u7, 14), @popCount(a1_rook));
    try std.testing.expectEqual(@as(u7, 7), @popCount(a1_bishop));
}

test "ray_table blocker masking on d4 north (d6) and south (d2)" {
    // Rook on d4 (27) with a blocker on d6 (43):
    // North ray from d4 masked by North ray from the first blocker (d6) leaves d5 (35) and d6 (43), excluding d7 (51) and d8 (59).
    const north_dir = @backingInt(RayDirection.north);
    const north_blockers = ray_table[north_dir][27] & squareBit(43);
    const first_north_blocker: brd.Square = @intCast(@ctz(north_blockers));
    const north_attacks = ray_table[north_dir][27] ^ ray_table[north_dir][first_north_blocker];
    try std.testing.expectEqual(squareBit(35) | squareBit(43), north_attacks);
    try std.testing.expectEqual(@as(u64, 0), north_attacks & (squareBit(51) | squareBit(59)));

    // Rook on d4 (27) with a blocker on d2 (11):
    // South ray from d4 masked by South ray from the first blocker (d2, highest bit via 63 - @clz) leaves d3 (19) and d2 (11), excluding d1 (3).
    const south_dir = @backingInt(RayDirection.south);
    const south_blockers = ray_table[south_dir][27] & squareBit(11);
    const first_south_blocker: brd.Square = @intCast(63 - @clz(south_blockers));
    const south_attacks = ray_table[south_dir][27] ^ ray_table[south_dir][first_south_blocker];
    try std.testing.expectEqual(squareBit(19) | squareBit(11), south_attacks);
    try std.testing.expectEqual(@as(u64, 0), south_attacks & squareBit(3));
}

test "ray_table totals across all 64 squares for rook, bishop, and queen" {
    var rook_total: u32 = 0;
    var bishop_total: u32 = 0;
    var queen_total: u32 = 0;

    for (0..64) |sq| {
        const rook_rays = ray_table[@backingInt(RayDirection.north)][sq] |
            ray_table[@backingInt(RayDirection.south)][sq] |
            ray_table[@backingInt(RayDirection.east)][sq] |
            ray_table[@backingInt(RayDirection.west)][sq];
        const bishop_rays = ray_table[@backingInt(RayDirection.northeast)][sq] |
            ray_table[@backingInt(RayDirection.northwest)][sq] |
            ray_table[@backingInt(RayDirection.southeast)][sq] |
            ray_table[@backingInt(RayDirection.southwest)][sq];
        const queen_rays = rook_rays | bishop_rays;

        rook_total += @popCount(rook_rays);
        bishop_total += @popCount(bishop_rays);
        queen_total += @popCount(queen_rays);
    }

    try std.testing.expectEqual(@as(u32, 896), rook_total);
    try std.testing.expectEqual(@as(u32, 560), bishop_total);
    try std.testing.expectEqual(@as(u32, 1456), queen_total);
}

test "ray_table opposite-direction symmetry" {
    const pairs = [_][2]RayDirection{
        .{ .north, .south },
        .{ .east, .west },
        .{ .northeast, .southwest },
        .{ .northwest, .southeast },
    };

    for (pairs) |pair| {
        const d_fwd = @backingInt(pair[0]);
        const d_rev = @backingInt(pair[1]);

        for (0..64) |i| {
            for (0..64) |j| {
                const j_in_fwd = (ray_table[d_fwd][i] & squareBit(@intCast(j))) != 0;
                const i_in_rev = (ray_table[d_rev][j] & squareBit(@intCast(i))) != 0;
                try std.testing.expectEqual(j_in_fwd, i_in_rev);
            }
        }
    }
}

const RayStep = struct { rank: i8, file: i8 };

/// Reference implementation: walk one square at a time in the given direction,
/// adding each square until the edge is reached or the first occupied square is hit.
fn naiveRayAttacks(comptime direction: RayDirection, from: brd.Square, occupancy: u64) u64 {
    const step: RayStep = switch (direction) {
        .north => .{ .rank = 1, .file = 0 },
        .northeast => .{ .rank = 1, .file = 1 },
        .northwest => .{ .rank = 1, .file = -1 },
        .east => .{ .rank = 0, .file = 1 },
        .south => .{ .rank = -1, .file = 0 },
        .southeast => .{ .rank = -1, .file = 1 },
        .southwest => .{ .rank = -1, .file = -1 },
        .west => .{ .rank = 0, .file = -1 },
    };

    var rank: i8 = @intCast(from / 8);
    var file: i8 = @intCast(from % 8);
    var attacks: u64 = 0;

    while (true) {
        rank += step.rank;
        file += step.file;
        if (rank < 0 or rank >= 8 or file < 0 or file >= 8) break;

        const sq: brd.Square = @intCast(rank * 8 + file);
        const bit = squareBit(sq);
        attacks |= bit;
        if (occupancy & bit != 0) break;
    }

    return attacks;
}

fn naiveRookAttacks(from: brd.Square, occupancy: u64) u64 {
    return naiveRayAttacks(.north, from, occupancy) |
        naiveRayAttacks(.east, from, occupancy) |
        naiveRayAttacks(.west, from, occupancy) |
        naiveRayAttacks(.south, from, occupancy);
}

fn naiveBishopAttacks(from: brd.Square, occupancy: u64) u64 {
    return naiveRayAttacks(.northeast, from, occupancy) |
        naiveRayAttacks(.northwest, from, occupancy) |
        naiveRayAttacks(.southeast, from, occupancy) |
        naiveRayAttacks(.southwest, from, occupancy);
}

fn naiveQueenAttacks(from: brd.Square, occupancy: u64) u64 {
    return naiveRookAttacks(from, occupancy) | naiveBishopAttacks(from, occupancy);
}

fn sliderTargets(comptime piece: Piece, from: brd.Square, occupancy: u64) u64 {
    return switch (piece) {
        .bishop => bishopAttacks(from, occupancy),
        .rook => rookAttacks(from, occupancy),
        .queen => queenAttacks(from, occupancy),
        else => @compileError("sliderTargets needs a bishop, rook, or queen"),
    };
}

/// Checks every move generated from `from`, including duplicates and flags.
fn expectMovesFrom(list: *const MoveList, from: brd.Square, expected_targets: u64, opponent_occupancy: u64) !void {
    var seen: u64 = 0;
    for (list.moves[0..list.count]) |m| {
        if (m.from != from) continue;

        const to_bit = squareBit(m.to);
        try std.testing.expectEqual(@as(u64, 0), seen & to_bit);
        seen |= to_bit;

        const expected_flags: MoveFlags = if (opponent_occupancy & to_bit != 0) .capture else .quiet_move;
        try std.testing.expectEqual(expected_flags, m.flags);
    }

    try std.testing.expectEqual(expected_targets, seen);
}

/// Compares sliderMoves against the direct attack functions for one color/piece type.
fn checkSliderMoves(board: *const Board, color: Color, comptime piece: Piece) !void {
    var list = MoveList{};
    sliderMoves(board, color, piece, &list);

    const own_occupancy = board.occupancy[@backingInt(color)];
    const opponent_occupancy = board.occupancy[@backingInt(color.opposite())];
    const occupancy = own_occupancy | opponent_occupancy;
    const pieces = board.getBoard(color, piece);

    var expected_count: usize = 0;
    var remaining = pieces;
    while (remaining != 0) : (remaining &= remaining - 1) {
        const from: brd.Square = @intCast(@ctz(remaining));
        const targets = sliderTargets(piece, from, occupancy) & ~own_occupancy;
        expected_count += @as(usize, @popCount(targets));
        try expectMovesFrom(&list, from, targets, opponent_occupancy);
    }

    try std.testing.expectEqual(expected_count, @as(usize, list.count));

    for (list.moves[0..list.count]) |m| {
        try std.testing.expect(pieces & squareBit(m.from) != 0);
    }
}

test "rayAttacks returns the full ray when the path is empty" {
    const from: brd.Square = 28; // e4

    try std.testing.expectEqual(
        squareBit(36) | squareBit(44) | squareBit(52) | squareBit(60), // e5-e8
        rayAttacks(.north, from, 0),
    );
    try std.testing.expectEqual(
        squareBit(20) | squareBit(12) | squareBit(4), // e3-e1
        rayAttacks(.south, from, 0),
    );
    try std.testing.expectEqual(
        squareBit(29) | squareBit(30) | squareBit(31), // f4-h4
        rayAttacks(.east, from, 0),
    );
    try std.testing.expectEqual(
        squareBit(27) | squareBit(26) | squareBit(25) | squareBit(24), // d4-a4
        rayAttacks(.west, from, 0),
    );
    try std.testing.expectEqual(
        squareBit(37) | squareBit(46) | squareBit(55), // f5-h7
        rayAttacks(.northeast, from, 0),
    );
    try std.testing.expectEqual(
        squareBit(35) | squareBit(42) | squareBit(49) | squareBit(56), // d5-a8
        rayAttacks(.northwest, from, 0),
    );
    try std.testing.expectEqual(
        squareBit(21) | squareBit(14) | squareBit(7), // f3-h1
        rayAttacks(.southeast, from, 0),
    );
    try std.testing.expectEqual(
        squareBit(19) | squareBit(10) | squareBit(1), // d3-b1
        rayAttacks(.southwest, from, 0),
    );
}

test "rayAttacks includes the first blocker and excludes squares behind it" {
    const from: brd.Square = 28; // e4

    try std.testing.expectEqual(
        squareBit(36) | squareBit(44), // e5, e6
        rayAttacks(.north, from, squareBit(44)),
    );
    try std.testing.expectEqual(
        squareBit(20) | squareBit(12), // e3, e2
        rayAttacks(.south, from, squareBit(12)),
    );
    try std.testing.expectEqual(
        squareBit(29) | squareBit(30), // f4, g4
        rayAttacks(.east, from, squareBit(30)),
    );
    try std.testing.expectEqual(
        squareBit(27) | squareBit(26), // d4, c4
        rayAttacks(.west, from, squareBit(26)),
    );
    try std.testing.expectEqual(
        squareBit(37) | squareBit(46), // f5, g6
        rayAttacks(.northeast, from, squareBit(46)),
    );
    try std.testing.expectEqual(
        squareBit(35) | squareBit(42), // d5, c6
        rayAttacks(.northwest, from, squareBit(42)),
    );
    try std.testing.expectEqual(
        squareBit(21) | squareBit(14), // f3, g2
        rayAttacks(.southeast, from, squareBit(14)),
    );
    try std.testing.expectEqual(
        squareBit(19) | squareBit(10), // d3, c2
        rayAttacks(.southwest, from, squareBit(10)),
    );
}

test "rayAttacks chooses the nearest blocker, ignores off-ray blockers, and ignores the origin" {
    const from: brd.Square = 28; // e4
    const full_north = squareBit(36) | squareBit(44) | squareBit(52) | squareBit(60);

    // Blockers on e6 and e7: only e6 and the squares before it are attacked.
    try std.testing.expectEqual(
        squareBit(36) | squareBit(44),
        rayAttacks(.north, from, squareBit(44) | squareBit(52)),
    );

    // An adjacent blocker is the only square returned on that ray.
    try std.testing.expectEqual(
        squareBit(36),
        rayAttacks(.north, from, squareBit(36) | squareBit(52)),
    );

    // A piece on the slider's own square does not block its own ray.
    try std.testing.expectEqual(full_north, rayAttacks(.north, from, squareBit(28)));

    // Blockers that are not on the ray do not affect it.
    try std.testing.expectEqual(
        full_north,
        rayAttacks(.north, from, squareBit(0) | squareBit(7) | squareBit(63)),
    );
}

test "rayAttacks from the corners stays on the board" {
    // a1 (0)
    try std.testing.expectEqual(
        squareBit(8) | squareBit(16) | squareBit(24), // a2-a4
        rayAttacks(.north, 0, squareBit(24)),
    );
    try std.testing.expectEqual(
        squareBit(1) | squareBit(2), // b1, c1
        rayAttacks(.east, 0, squareBit(2)),
    );
    try std.testing.expectEqual(
        squareBit(9) | squareBit(18), // b2, c3
        rayAttacks(.northeast, 0, squareBit(18)),
    );

    // h8 (63)
    try std.testing.expectEqual(
        squareBit(55) | squareBit(47), // h7, h6
        rayAttacks(.south, 63, squareBit(47)),
    );
    try std.testing.expectEqual(
        squareBit(62) | squareBit(61), // g8, f8
        rayAttacks(.west, 63, squareBit(61)),
    );
    try std.testing.expectEqual(
        squareBit(54) | squareBit(45), // g7, f6
        rayAttacks(.southwest, 63, squareBit(45)),
    );
}

test "rayAttacks stops at a single blocker from every square in every direction" {
    inline for (std.enums.values(RayDirection)) |direction| {
        for (0..64) |from_index| {
            const from: brd.Square = @intCast(from_index);

            for (0..64) |blocker_index| {
                const occupancy = squareBit(@intCast(blocker_index));
                try std.testing.expectEqual(
                    naiveRayAttacks(direction, from, occupancy),
                    rayAttacks(direction, from, occupancy),
                );
            }
        }
    }
}

test "rayAttacks matches a naive walk for every square and random occupancies (fixed seed)" {
    var prng = std.Random.DefaultPrng.init(0x9E37_79B9_7F4A_7C15);
    const random = prng.random();

    var iteration: usize = 0;
    while (iteration < 3000) : (iteration += 1) {
        // Keep a guaranteed empty-board case, then use dense random occupancies.
        const occupancy: u64 = if (iteration == 0) 0 else random.int(u64);

        inline for (std.enums.values(RayDirection)) |direction| {
            for (0..64) |sq| {
                const from: brd.Square = @intCast(sq);
                try std.testing.expectEqual(
                    naiveRayAttacks(direction, from, occupancy),
                    rayAttacks(direction, from, occupancy),
                );
            }
        }
    }
}

test "rookAttacks covers the full rank and file on an empty board" {
    const from: brd.Square = 28; // e4
    const expected = squareBit(36) | squareBit(44) | squareBit(52) | squareBit(60) | // e5-e8
        squareBit(20) | squareBit(12) | squareBit(4) | // e3-e1
        squareBit(29) | squareBit(30) | squareBit(31) | // f4-h4
        squareBit(27) | squareBit(26) | squareBit(25) | squareBit(24); // d4-a4

    try std.testing.expectEqual(expected, rookAttacks(from, 0));
    try std.testing.expectEqual(@as(u7, 14), @popCount(expected));
    try std.testing.expectEqual(expected, rookAttacks(from, squareBit(from)));
}

test "rookAttacks stops at the nearest blocker on each ray" {
    // Rook on e4 with blockers on e6, c4, e2, and g4.
    const occupancy = squareBit(44) | squareBit(26) | squareBit(12) | squareBit(30);
    const expected = squareBit(36) | squareBit(44) | // e5, e6
        squareBit(20) | squareBit(12) | // e3, e2
        squareBit(29) | squareBit(30) | // f4, g4
        squareBit(27) | squareBit(26); // d4, c4

    const attacks = rookAttacks(28, occupancy);
    try std.testing.expectEqual(expected, attacks);
    try std.testing.expectEqual(@as(u7, 8), @popCount(attacks));

    // Nothing past any of the blockers.
    try std.testing.expectEqual(@as(u64, 0), attacks & (squareBit(52) | squareBit(25) | squareBit(4) | squareBit(31)));
}

test "rookAttacks with a fully occupied board only reaches adjacent squares" {
    const occupancy: u64 = ~@as(u64, 0);

    try std.testing.expectEqual(
        squareBit(36) | squareBit(29) | squareBit(20) | squareBit(27), // e5, f4, e3, d4
        rookAttacks(28, occupancy),
    );
    try std.testing.expectEqual(
        squareBit(8) | squareBit(1), // a2, b1
        rookAttacks(0, occupancy),
    );
    try std.testing.expectEqual(
        squareBit(55) | squareBit(62), // h7, g8
        rookAttacks(63, occupancy),
    );
}

test "bishopAttacks covers both diagonals on an empty board" {
    const from: brd.Square = 28; // e4
    const expected = squareBit(37) | squareBit(46) | squareBit(55) | // f5-h7
        squareBit(35) | squareBit(42) | squareBit(49) | squareBit(56) | // d5-a8
        squareBit(21) | squareBit(14) | squareBit(7) | // f3-h1
        squareBit(19) | squareBit(10) | squareBit(1); // d3-b1

    try std.testing.expectEqual(expected, bishopAttacks(from, 0));
    try std.testing.expectEqual(@as(u7, 13), @popCount(expected));
    try std.testing.expectEqual(expected, bishopAttacks(from, squareBit(from)));
}

test "bishopAttacks stops on the first blocker of each diagonal" {
    // Bishop on e4 with blockers on c6 and g2.
    const occupancy = squareBit(42) | squareBit(14);
    const expected = squareBit(37) | squareBit(46) | squareBit(55) | // f5, g6, h7
        squareBit(35) | squareBit(42) | // d5, c6
        squareBit(21) | squareBit(14) | // f3, g2
        squareBit(19) | squareBit(10) | squareBit(1); // d3, c2, b1

    const attacks = bishopAttacks(28, occupancy);
    try std.testing.expectEqual(expected, attacks);
    try std.testing.expectEqual(@as(u7, 10), @popCount(attacks));

    // Nothing behind c6 or g2.
    try std.testing.expectEqual(@as(u64, 0), attacks & (squareBit(49) | squareBit(56) | squareBit(7)));
}

test "bishopAttacks with a fully occupied board only reaches adjacent diagonals" {
    const occupancy: u64 = ~@as(u64, 0);

    try std.testing.expectEqual(
        squareBit(35) | squareBit(37) | squareBit(19) | squareBit(21), // d5, f5, d3, f3
        bishopAttacks(28, occupancy),
    );
    try std.testing.expectEqual(squareBit(9), bishopAttacks(0, occupancy)); // b2 only
    try std.testing.expectEqual(squareBit(54), bishopAttacks(63, occupancy)); // g7 only
}

test "queenAttacks combines rook and bishop rays" {
    const from: brd.Square = 28; // e4
    const empty_expected = rookAttacks(from, 0) | bishopAttacks(from, 0);

    try std.testing.expectEqual(empty_expected, queenAttacks(from, 0));
    try std.testing.expectEqual(@as(u7, 27), @popCount(empty_expected));

    // Queen on e4 with blockers on e6, c6, c4, and g2.
    const occupancy = squareBit(44) | squareBit(42) | squareBit(26) | squareBit(14);
    const expected = squareBit(36) | squareBit(44) | // e5, e6
        squareBit(20) | squareBit(12) | squareBit(4) | // e3-e1
        squareBit(29) | squareBit(30) | squareBit(31) | // f4-h4
        squareBit(27) | squareBit(26) | // d4, c4
        squareBit(37) | squareBit(46) | squareBit(55) | // f5-h7
        squareBit(35) | squareBit(42) | // d5, c6
        squareBit(21) | squareBit(14) | // f3, g2
        squareBit(19) | squareBit(10) | squareBit(1); // d3-b1

    try std.testing.expectEqual(expected, queenAttacks(from, occupancy));
    try std.testing.expectEqual(@as(u7, 20), @popCount(expected));
    try std.testing.expectEqual(expected, rookAttacks(from, occupancy) | bishopAttacks(from, occupancy));
}

test "rook, bishop, and queen attacks match naive walks for every square and random occupancies" {
    var prng = std.Random.DefaultPrng.init(0xD1B5_4A32_D192_ED03);
    const random = prng.random();

    var iteration: usize = 0;
    while (iteration < 3000) : (iteration += 1) {
        const occupancy: u64 = if (iteration == 0) 0 else random.int(u64);

        for (0..64) |sq| {
            const from: brd.Square = @intCast(sq);
            try std.testing.expectEqual(
                naiveRookAttacks(from, occupancy),
                rookAttacks(from, occupancy),
            );
            try std.testing.expectEqual(
                naiveBishopAttacks(from, occupancy),
                bishopAttacks(from, occupancy),
            );
            try std.testing.expectEqual(
                naiveQueenAttacks(from, occupancy),
                queenAttacks(from, occupancy),
            );
        }
    }
}

test "sliderMoves generates all rook moves on an empty board" {
    var board = brd.empty;
    board.setPiece(.white, .rook, 28); // e4

    var list = MoveList{};
    sliderMoves(&board, .white, .rook, &list);

    const expected = squareBit(36) | squareBit(44) | squareBit(52) | squareBit(60) | // e5-e8
        squareBit(20) | squareBit(12) | squareBit(4) | // e3-e1
        squareBit(29) | squareBit(30) | squareBit(31) | // f4-h4
        squareBit(27) | squareBit(26) | squareBit(25) | squareBit(24); // d4-a4

    try std.testing.expectEqual(@as(u16, 14), list.count);
    try expectMovesFrom(&list, 28, expected, 0);
}

test "sliderMoves includes a capture but stops at a friendly piece for a rook" {
    // White rook e4, friendly pawn e2, black pawn e6.
    var board = brd.empty;
    board.setPiece(.white, .rook, 28);
    board.setPiece(.white, .pawn, 12);
    board.setPiece(.black, .pawn, 44);

    var list = MoveList{};
    sliderMoves(&board, .white, .rook, &list);

    const expected = squareBit(36) | squareBit(44) | // e5, capture e6
        squareBit(20) | // e3; e2 is friendly
        squareBit(29) | squareBit(30) | squareBit(31) | // f4-h4
        squareBit(27) | squareBit(26) | squareBit(25) | squareBit(24); // d4-a4

    try std.testing.expectEqual(@as(u16, 10), list.count);
    try expectMovesFrom(&list, 28, expected, board.occupancy[@backingInt(Color.black)]);

    for (list.moves[0..list.count]) |m| {
        try std.testing.expect(m.to != 12); // friendly pawn itself
        try std.testing.expect(m.to != 52); // beyond the captured pawn
    }
}

test "sliderMoves handles captures and friendly blockers for a bishop" {
    // White bishop e4, black knight c6, white knight g2.
    var board = brd.empty;
    board.setPiece(.white, .bishop, 28);
    board.setPiece(.black, .knight, 42);
    board.setPiece(.white, .knight, 14);

    var list = MoveList{};
    sliderMoves(&board, .white, .bishop, &list);

    const expected = squareBit(37) | squareBit(46) | squareBit(55) | // f5, g6, h7
        squareBit(35) | squareBit(42) | // d5, capture c6
        squareBit(21) | // f3; g2 is friendly
        squareBit(19) | squareBit(10) | squareBit(1); // d3, c2, b1

    try std.testing.expectEqual(@as(u16, 9), list.count);
    try expectMovesFrom(&list, 28, expected, board.occupancy[@backingInt(Color.black)]);

    for (list.moves[0..list.count]) |m| {
        try std.testing.expect(m.to != 14); // friendly knight itself
        try std.testing.expect(m.to != 7); // beyond the friendly knight
        try std.testing.expect(m.to != 49); // beyond c6
        try std.testing.expect(m.to != 56); // beyond c6
    }
}

test "sliderMoves combines rook and bishop rays for a queen" {
    // White queen e4, black pawn e6, black knight c6, white pawn c4, black bishop g2.
    var board = brd.empty;
    board.setPiece(.white, .queen, 28);
    board.setPiece(.black, .pawn, 44);
    board.setPiece(.black, .knight, 42);
    board.setPiece(.white, .pawn, 26);
    board.setPiece(.black, .bishop, 14);

    var list = MoveList{};
    sliderMoves(&board, .white, .queen, &list);

    const expected = squareBit(36) | squareBit(44) | // e5, capture e6
        squareBit(20) | squareBit(12) | squareBit(4) | // e3-e1
        squareBit(29) | squareBit(30) | squareBit(31) | // f4-h4
        squareBit(27) | // d4; c4 is friendly
        squareBit(37) | squareBit(46) | squareBit(55) | // f5-h7
        squareBit(35) | squareBit(42) | // d5, capture c6
        squareBit(21) | squareBit(14) | // f3, capture g2
        squareBit(19) | squareBit(10) | squareBit(1); // d3, c2, b1

    try std.testing.expectEqual(@as(u16, 19), list.count);
    try expectMovesFrom(&list, 28, expected, board.occupancy[@backingInt(Color.black)]);
}

test "sliderMoves handles multiple sliders of the same type" {
    var board = brd.empty;
    board.setPiece(.white, .rook, 0); // a1
    board.setPiece(.white, .rook, 63); // h8

    var list = MoveList{};
    sliderMoves(&board, .white, .rook, &list);

    const a1_expected = squareBit(8) | squareBit(16) | squareBit(24) | squareBit(32) |
        squareBit(40) | squareBit(48) | squareBit(56) | // a2-a8
        squareBit(1) | squareBit(2) | squareBit(3) | squareBit(4) |
        squareBit(5) | squareBit(6) | squareBit(7); // b1-h1

    const h8_expected = squareBit(55) | squareBit(47) | squareBit(39) | squareBit(31) |
        squareBit(23) | squareBit(15) | squareBit(7) | // h7-h1
        squareBit(62) | squareBit(61) | squareBit(60) | squareBit(59) |
        squareBit(58) | squareBit(57) | squareBit(56); // g8-a8

    try std.testing.expectEqual(@as(u16, 28), list.count);
    try expectMovesFrom(&list, 0, a1_expected, 0);
    try expectMovesFrom(&list, 63, h8_expected, 0);
}

test "sliderMoves generates nothing when the side has no sliders" {
    var board = brd.empty;
    board.setPiece(.white, .knight, 28);
    board.setPiece(.black, .rook, 0);

    var rook_list = MoveList{};
    sliderMoves(&board, .white, .rook, &rook_list);
    try std.testing.expectEqual(@as(u16, 0), rook_list.count);

    var queen_list = MoveList{};
    sliderMoves(&board, .white, .queen, &queen_list);
    try std.testing.expectEqual(@as(u16, 0), queen_list.count);
}

test "sliderMoves matches direct slider attacks on random boards (fixed seed)" {
    var prng = std.Random.DefaultPrng.init(0xD1CE_5EED_1234_5678);
    const random = prng.random();
    const colors = [_]Color{ .white, .black };

    var iteration: usize = 0;
    while (iteration < 300) : (iteration += 1) {
        var board = brd.empty;
        var occupied: u64 = 0;

        // At most 8 pieces keeps the maximum possible move count below MoveList's capacity.
        const piece_count = random.intRangeAtMost(usize, 0, 8);
        var placed: usize = 0;
        while (placed < piece_count) {
            const sq: brd.Square = random.int(brd.Square);
            const bit = squareBit(sq);
            if (occupied & bit != 0) continue;

            occupied |= bit;
            const color: Color = if (random.boolean()) .white else .black;
            const piece: Piece = @fromBackingInt(@intCast(random.uintLessThan(u8, 6)));
            board.setPiece(color, piece, sq);
            placed += 1;
        }

        for (colors) |color| {
            try checkSliderMoves(&board, color, .bishop);
            try checkSliderMoves(&board, color, .rook);
            try checkSliderMoves(&board, color, .queen);
        }
    }
}
