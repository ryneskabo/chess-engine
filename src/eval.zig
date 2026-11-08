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

pub fn evaluateMaterial(board: *const brd.Board) i64 {
    const white_pawn_value: i64 = @as(i64, @intCast(@popCount(board.getBoard(.white, .pawn)))) * pawn_value;
    const black_pawn_value: i64 = @as(i64, @intCast(@popCount(board.getBoard(.black, .pawn)))) * pawn_value;

    const white_knight_value: i64 = @as(i64, @intCast(@popCount(board.getBoard(.white, .knight)))) * knight_value;
    const black_knight_value: i64 = @as(i64, @intCast(@popCount(board.getBoard(.black, .knight)))) * knight_value;

    const white_bishop_value: i64 = @as(i64, @intCast(@popCount(board.getBoard(.white, .bishop)))) * bishop_value;
    const black_bishop_value: i64 = @as(i64, @intCast(@popCount(board.getBoard(.black, .bishop)))) * bishop_value;

    const white_rook_value: i64 = @as(i64, @intCast(@popCount(board.getBoard(.white, .rook)))) * rook_value;
    const black_rook_value: i64 = @as(i64, @intCast(@popCount(board.getBoard(.black, .rook)))) * rook_value;

    const white_queen_value: i64 = @as(i64, @intCast(@popCount(board.getBoard(.white, .queen)))) * queen_value;
    const black_queen_value: i64 = @as(i64, @intCast(@popCount(board.getBoard(.black, .queen)))) * queen_value;

    const white_value = white_pawn_value + white_knight_value + white_bishop_value + white_rook_value + white_queen_value;
    const black_value = black_pawn_value + black_knight_value + black_bishop_value + black_rook_value + black_queen_value;

    return if (board.side_to_move == .white) white_value - black_value else black_value - white_value;
}

pub fn evaluate(board: *const brd.Board) i64 {
    const white_pawn_board = board.getBoard(.white, .pawn);
    const white_pawn_value: i64 = @as(i64, @intCast(@popCount(white_pawn_board))) * pawn_value + positionEvaluation(board, white_pawn_board, .pawn);
    const black_pawn_board = board.getBoard(.black, .pawn);
    const black_pawn_value: i64 = @as(i64, @intCast(@popCount(black_pawn_board))) * pawn_value + positionEvaluation(board, @byteSwap(black_pawn_board), .pawn);

    const white_knight_board = board.getBoard(.white, .knight);
    const white_knight_value: i64 = @as(i64, @intCast(@popCount(white_knight_board))) * knight_value + positionEvaluation(board, white_knight_board, .knight);
    const black_knight_board = board.getBoard(.black, .knight);
    const black_knight_value: i64 = @as(i64, @intCast(@popCount(black_knight_board))) * knight_value + positionEvaluation(board, @byteSwap(black_knight_board), .knight);

    const white_bishop_board = board.getBoard(.white, .bishop);
    const white_bishop_value: i64 = @as(i64, @intCast(@popCount(white_bishop_board))) * bishop_value + positionEvaluation(board, white_bishop_board, .bishop);
    const black_bishop_board = board.getBoard(.black, .bishop);
    const black_bishop_value: i64 = @as(i64, @intCast(@popCount(black_bishop_board))) * bishop_value + positionEvaluation(board, @byteSwap(black_bishop_board), .bishop);

    const white_rook_board = board.getBoard(.white, .rook);
    const white_rook_value: i64 = @as(i64, @intCast(@popCount(white_rook_board))) * rook_value + positionEvaluation(board, white_rook_board, .rook);
    const black_rook_board = board.getBoard(.black, .rook);
    const black_rook_value: i64 = @as(i64, @intCast(@popCount(black_rook_board))) * rook_value + positionEvaluation(board, @byteSwap(black_rook_board), .rook);

    const white_queen_board = board.getBoard(.white, .queen);
    const white_queen_value: i64 = @as(i64, @intCast(@popCount(white_queen_board))) * queen_value + positionEvaluation(board, white_queen_board, .queen);
    const black_queen_board = board.getBoard(.black, .queen);
    const black_queen_value: i64 = @as(i64, @intCast(@popCount(black_queen_board))) * queen_value + positionEvaluation(board, @byteSwap(black_queen_board), .queen);

    const white_king_value: i64 = positionEvaluation(board, board.getBoard(.white, .king), .king);
    const black_king_value: i64 = positionEvaluation(board, @byteSwap(board.getBoard(.black, .king)), .king);

    const white_value = white_pawn_value + white_knight_value + white_bishop_value + white_rook_value + white_queen_value + white_king_value;
    const black_value = black_pawn_value + black_knight_value + black_bishop_value + black_rook_value + black_queen_value + black_king_value;

    return if (board.side_to_move == .white) white_value - black_value else black_value - white_value;
}

fn positionEvaluation(board: *const brd.Board, piece_board: u64, comptime piece: brd.Piece) i64 {
    const piece_table = switch (piece) {
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
