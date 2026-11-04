const std = @import("std");
const brd = @import("../board.zig");
const rays = @import("../attacks/sliders.zig");
const move = @import("move.zig");

const Board = brd.Board;
const Color = brd.Color;
const Piece = brd.Piece;

const MoveFlags = move.MoveFlags;
const MoveList = move.MoveList;
const addMovesFromTargets = move.addMovesFromTargets;

const squareBit = brd.squareBit;

const bishopAttacks = rays.bishopAttacks;
const rookAttacks = rays.rookAttacks;
const queenAttacks = rays.queenAttacks;

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
