const std = @import("std");
const brd = @import("board.zig");
const fen = @import("fen.zig");
// values sourced from chess programming wiki's simplified evaluation page
const pawn_value = 100;
const knight_value = 320;
const bishop_value = 330;
const rook_value = 500;
const queen_value = 900;
const king_value = 0; // doesn't matter directly as kings cannot be captured

const pawn_square_table = [64]i16{
    0, 0, 0, 0, 0, 0, 0, 0, // not legal for pawn to stand on rank 1
    5, 10, 10,  -20, -20, 10,  10, 5, // encourage central pawn pushes, discourage pushing pawns in front of potentially castled king
    5, -5, -10, 0,   0,   -10, -5, 5,
    0, 0,  0,   20,  20,  0,   0,  0,
    5,  5,  10, 25, 25, 10, 5,  5, // central pawns good
    10, 10, 20, 30, 30, 20, 10, 10,
    50, 50, 50, 50, 50, 50, 50, 50, // pawn closer to promotion is better
    0, 0, 0, 0, 0, 0, 0, 0, // not legal for pawn to stand on rank 8
};

const knight_square_table = [64]i16{
    -50, -40, -30, -30, -30, -30, -40, -50,
    -40, -20, 0,   5,   5,   0,   -20, -40,
    -30, 5,   10,  15,  15,  10,  5,   -30,
    -30, 0,   15,  20,  20,  15,  0,   -30,
    -30, 5,   15,  20,  20,  15,  5,   -30,
    -30, 0,   10,  15,  15,  10,  0,   -30,
    -40, -20, 0,   0,   0,   0,   -20, -40,
    -50, -40, -30, -30, -30, -30, -40, -50,
};

const bishop_square_table = [64]i16{
    -20, -10, -10, -10, -10, -10, -10, -20,
    -10, 5,   0,   0,   0,   0,   5,   -10,
    -10, 10,  10,  10,  10,  10,  10,  -10,
    -10, 0,   10,  10,  10,  10,  0,   -10,
    -10, 5,   5,   10,  10,  5,   5,   -10,
    -10, 0,   5,   10,  10,  5,   0,   -10,
    -10, 0,   0,   0,   0,   0,   0,   -10,
    -20, -10, -10, -10, -10, -10, -10, -20,
};

const rook_square_table = [64]i16{
    0,  0,  0,  5,  5,  0,  0,  0,
    -5, 0,  0,  0,  0,  0,  0,  -5,
    -5, 0,  0,  0,  0,  0,  0,  -5,
    -5, 0,  0,  0,  0,  0,  0,  -5,
    -5, 0,  0,  0,  0,  0,  0,  -5,
    -5, 0,  0,  0,  0,  0,  0,  -5,
    5,  10, 10, 10, 10, 10, 10, 5,
    0,  0,  0,  0,  0,  0,  0,  0,
};

const queen_square_table = [64]i16{
    -20, -10, -10, -5, -5, -10, -10, -20,
    -10, 0,   5,   0,  0,  0,   0,   -10,
    -10, 5,   5,   5,  5,  5,   0,   -10,
    0,   0,   5,   5,  5,  5,   0,   -5,
    -5,  0,   5,   5,  5,  5,   0,   -5,
    -10, 0,   5,   5,  5,  5,   0,   -10,
    -10, 0,   0,   0,  0,  0,   0,   -10,
    -20, -10, -10, -5, -5, -10, -10, -20,
};

const king_middlegame_square_table = [64]i16{
    20,  30,  10,  0,   0,   10,  30,  20,
    20,  20,  0,   0,   0,   0,   20,  20,
    -10, -20, -20, -20, -20, -20, -20, -10,
    -20, -30, -30, -40, -40, -30, -30, -20,
    -30, -40, -40, -50, -50, -40, -40, -30,
    -30, -40, -40, -50, -50, -40, -40, -30,
    -30, -40, -40, -50, -50, -40, -40, -30,
    -30, -40, -40, -50, -50, -40, -40, -30,
};

const king_endgame_square_table = [64]i16{
    -50, -30, -30, -30, -30, -30, -30, -50,
    -30, -30, 0,   0,   0,   0,   -30, -30,
    -30, -10, 20,  30,  30,  20,  -10, -30,
    -30, -10, 30,  40,  40,  30,  -10, -30,
    -30, -10, 30,  40,  40,  30,  -10, -30,
    -30, -10, 20,  30,  30,  20,  -10, -30,
    -30, -20, -10, 0,   0,   -10, -20, -30,
    -50, -40, -30, -20, -20, -30, -40, -50,
};

fn pieceValue(piece: brd.Piece) i64 {
    return switch (piece) {
        .pawn => pawn_value,
        .knight => knight_value,
        .bishop => bishop_value,
        .rook => rook_value,
        .queen => queen_value,
        .king => king_value,
    };
}

pub fn evaluateMaterial(board: *const brd.Board) i64 {
    var white_value: i64 = 0;
    var black_value: i64 = 0;

    inline for (std.enums.values(brd.Piece)) |piece| {
        const value = pieceValue(piece);
        white_value += @as(i64, @intCast(@popCount(board.getBoard(.white, piece)))) * value;
        black_value += @as(i64, @intCast(@popCount(board.getBoard(.black, piece)))) * value;
    }

    return if (board.side_to_move == .white) white_value - black_value else black_value - white_value;
}

pub fn evaluate(board: *const brd.Board) i64 {
    var white_position: i64 = 0;
    var black_position: i64 = 0;

    inline for (std.enums.values(brd.Piece)) |piece| {
        const piece_table = pieceSquareTable(board, piece);
        white_position += positionEvaluation(board.getBoard(.white, piece), piece_table);
        black_position += positionEvaluation(@byteSwap(board.getBoard(.black, piece)), piece_table);
    }

    const position_value = if (board.side_to_move == .white) white_position - black_position else black_position - white_position;
    return evaluateMaterial(board) + position_value;
}

fn pieceSquareTable(board: *const brd.Board, piece: brd.Piece) *const [64]i16 {
    return switch (piece) {
        .pawn => &pawn_square_table,
        .knight => &knight_square_table,
        .bishop => &bishop_square_table,
        .rook => &rook_square_table,
        .queen => &queen_square_table,
        .king => blk: {
            const white_has_queen = board.getBoard(.white, .queen) != 0;
            const black_has_queen = board.getBoard(.black, .queen) != 0;
            if (!(white_has_queen or black_has_queen)) {
                break :blk &king_endgame_square_table;
            }

            const white_has_rook = board.getBoard(.white, .rook) != 0;
            const black_has_rook = board.getBoard(.black, .rook) != 0;
            if (white_has_queen and white_has_rook or black_has_queen and black_has_rook) {
                break :blk &king_middlegame_square_table;
            }
            const white_minor_count = @popCount(board.getBoard(.white, .knight)) + @popCount(board.getBoard(.white, .bishop));
            const black_minor_count = @popCount(board.getBoard(.black, .knight)) + @popCount(board.getBoard(.black, .bishop));

            if (white_has_queen and white_minor_count > 1 or black_has_queen and black_minor_count > 1) {
                break :blk &king_middlegame_square_table;
            }

            break :blk &king_endgame_square_table;
        },
    };
}

fn positionEvaluation(piece_board: u64, piece_table: *const [64]i16) i64 {
    var bb = piece_board;
    var sum: i64 = 0;
    while (bb != 0) : (bb &= bb - 1) {
        const square: brd.Square = @intCast(@ctz(bb));
        sum += piece_table[square];
    }
    return sum;
}

fn mirrorBoard(board: *const brd.Board) brd.Board {
    var mirrored = board.*;
    for (0..6) |piece_idx| {
        mirrored.pieces[@backingInt(brd.Color.white)][piece_idx] = @byteSwap(board.pieces[@backingInt(brd.Color.black)][piece_idx]);
        mirrored.pieces[@backingInt(brd.Color.black)][piece_idx] = @byteSwap(board.pieces[@backingInt(brd.Color.white)][piece_idx]);
    }
    mirrored.occupancy[@backingInt(brd.Color.white)] = @byteSwap(board.occupancy[@backingInt(brd.Color.black)]);
    mirrored.occupancy[@backingInt(brd.Color.black)] = @byteSwap(board.occupancy[@backingInt(brd.Color.white)]);
    mirrored.side_to_move = board.side_to_move.opposite();
    return mirrored;
}

test "starting position evaluates to 0 for either side to move" {
    var board = try fen.parseFen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");
    try std.testing.expectEqual(@as(i64, 0), evaluate(&board));

    board.side_to_move = .black;
    try std.testing.expectEqual(@as(i64, 0), evaluate(&board));
}

test "removing one white pawn from starting position scores pawn value plus table value for black" {
    const start = try fen.parseFen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR b KQkq - 0 1");

    // Check every rank-2 white pawn square (a2 = 8 through h2 = 15)
    for (8..16) |sq_usize| {
        const sq: brd.Square = @intCast(sq_usize);
        var board = start;
        board.removePiece(.white, .pawn, sq);

        const expected_for_black: i64 = pawn_value + pawn_square_table[sq];
        try std.testing.expectEqual(expected_for_black, evaluate(&board));

        board.side_to_move = .white;
        try std.testing.expectEqual(-expected_for_black, evaluate(&board));
    }
}

test "mirroring colors, ranks, and side to move preserves evaluation" {
    const positions = [_][]const u8{
        // Starting position
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
        // Kiwipete
        "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
        // Perft position 3 (endgame without queens)
        "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1",
        // Perft position 4 (imbalanced material, middlegame)
        "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1",
        // Perft position 5
        "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8",
        // Perft position 6
        "r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10",
    };

    for (positions) |fen_str| {
        var board = try fen.parseFen(fen_str);
        const mirrored_from_white = mirrorBoard(&board);
        try std.testing.expectEqual(evaluate(&board), evaluate(&mirrored_from_white));

        board.side_to_move = .black;
        const mirrored_from_black = mirrorBoard(&board);
        try std.testing.expectEqual(evaluate(&board), evaluate(&mirrored_from_black));
    }
}

test "evaluateMaterial matches hand-counted totals" {
    const cases = [_]struct {
        fen: []const u8,
        expected_white: i64,
    }{
        // Starting position: equal material (4000 - 4000 = 0)
        .{
            .fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            .expected_white = 0,
        },
        // Perft position 4: White has 8 pawns vs Black's 7 pawns (all other pieces equal) -> +100 for White
        .{
            .fen = "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1",
            .expected_white = pawn_value,
        },
        // Perft position 5: both sides have 6P, 2N, 2B, 2R, 1Q (3800 - 3800 = 0)
        .{
            .fen = "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8",
            .expected_white = 0,
        },
        // White has Q(900) + B(330) + P(100) = 1330; Black has R(500) + N(320) = 820 -> +510 for White
        .{
            .fen = "3rk3/2n5/8/8/8/8/4P3/2B1K2Q w - - 0 1",
            .expected_white = (queen_value + bishop_value + pawn_value) - (rook_value + knight_value),
        },
        // Endgame: White has R(500) + 2P(200) = 700; Black has B(330) + N(320) + P(100) = 750 -> -50 for White
        .{
            .fen = "4k3/3p4/2nb4/8/8/8/1PP5/3RK3 w - - 0 1",
            .expected_white = (rook_value + 2 * pawn_value) - (bishop_value + knight_value + pawn_value),
        },
    };

    for (cases) |case| {
        var board = try fen.parseFen(case.fen);
        try std.testing.expectEqual(case.expected_white, evaluateMaterial(&board));

        board.side_to_move = .black;
        try std.testing.expectEqual(-case.expected_white, evaluateMaterial(&board));
    }
}

test "piece-square table orientation" {
    // A white pawn on e4 scores higher than a white pawn on e2
    const white_pawn_e4 = try fen.parseFen("4k3/8/8/8/4P3/8/8/4K3 w - - 0 1");
    const white_pawn_e2 = try fen.parseFen("4k3/8/8/8/8/8/4P3/4K3 w - - 0 1");
    try std.testing.expect(evaluate(&white_pawn_e4) > evaluate(&white_pawn_e2));

    // A black pawn on e5 scores higher for black than a black pawn on e7
    const black_pawn_e5 = try fen.parseFen("4k3/8/8/4p3/8/8/8/4K3 b - - 0 1");
    const black_pawn_e7 = try fen.parseFen("4k3/4p3/8/8/8/8/8/4K3 b - - 0 1");
    try std.testing.expect(evaluate(&black_pawn_e5) > evaluate(&black_pawn_e7));

    // A white knight on e4 scores higher than a white knight on a1
    const white_knight_e4 = try fen.parseFen("4k3/8/8/8/4N3/8/8/4K3 w - - 0 1");
    const white_knight_a1 = try fen.parseFen("4k3/8/8/8/8/8/8/N3K3 w - - 0 1");
    try std.testing.expect(evaluate(&white_knight_e4) > evaluate(&white_knight_a1));

    // Middlegame (queens and rooks on the board): a white king on g1 scores higher than on e4
    const white_king_g1_mg = try fen.parseFen("r2qk2r/8/8/8/8/8/8/R2Q2KR w - - 0 1");
    const white_king_e4_mg = try fen.parseFen("r2qk2r/8/8/8/4K3/8/8/R2Q3R w - - 0 1");
    try std.testing.expect(evaluate(&white_king_g1_mg) > evaluate(&white_king_e4_mg));

    // A white pawn on rank 7 scores much higher than the same pawn on rank 2
    for (0..8) |file| {
        var rank7_board = try fen.parseFen("4k3/8/8/8/8/8/8/4K3 w - - 0 1");
        var rank2_board = rank7_board;

        const rank7_sq: brd.Square = @intCast(6 * 8 + file);
        const rank2_sq: brd.Square = @intCast(1 * 8 + file);
        rank7_board.setPiece(.white, .pawn, rank7_sq);
        rank2_board.setPiece(.white, .pawn, rank2_sq);

        try std.testing.expect(evaluate(&rank7_board) - evaluate(&rank2_board) >= 40);
    }
}
