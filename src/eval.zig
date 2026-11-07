const std = @import("std");
const brd = @import("board.zig");
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

pub fn evaluate(board: *brd.Board) i64 {
    const white_pawn_board = board.getBoard(.white, .pawn);
    const white_pawn_value: i64 = @popCount(white_pawn_board) * pawn_value + positionEvaluation(white_pawn_board, .pawn);
    const black_pawn_board = board.getBoard(.black, .pawn);
    const black_pawn_value: i64 = @popCount(black_pawn_board) * pawn_value + positionEvaluation(black_pawn_board, .pawn);

    const white_knight_board = board.getBoard(.white, .knight);
    const white_knight_value: i64 = @popCount(white_knight_board) * knight_value + positionEvaluation(white_knight_board, .knight);
    const black_knight_board = board.getBoard(.black, .knight);
    const black_knight_value: i64 = @popCount(black_knight_board) * knight_value + positionEvaluation(black_knight_board, .knight);

    const white_bishop_board = board.getBoard(.white, .bishop);
    const white_bishop_value: i64 = @popCount(white_bishop_board) * bishop_value + positionEvaluation(white_bishop_board, .bishop);
    const black_bishop_board = board.getBoard(.black, .bishop);
    const black_bishop_value: i64 = @popCount(black_bishop_board) * bishop_value + positionEvaluation(black_bishop_board, .bishop);

    const white_rook_board = board.getBoard(.white, .rook);
    const white_rook_value: i64 = @popCount(white_rook_board) * rook_value + positionEvaluation(white_rook_board, .rook);
    const black_rook_board = board.getBoard(.black, .rook);
    const black_rook_value: i64 = @popCount(black_rook_board) * rook_value + positionEvaluation(black_rook_board, .rook);

    const white_queen_board = board.getBoard(.white, .queen);
    const white_queen_value: i64 = @popCount(white_queen_board) * rook_value + positionEvaluation(white_queen_board, .queen);
    const black_queen_board = board.getBoard(.black, .queen);
    const black_queen_value: i64 = @popCount(black_queen_board) * rook_value + positionEvaluation(black_queen_board, .queen);

    const white_king_value: i64 = positionEvaluation(board.getBoard(.white, .king), .king);
    const black_king_value: i64 = positionEvaluation(board.getBoard(.black, .king), .king);

    const white_value = white_pawn_value + white_knight_value + white_bishop_value + white_rook_value + white_queen_value + white_king_value;
    const black_value = black_pawn_value + black_knight_value + black_bishop_value + black_rook_value + black_queen_value + black_king_value;

    return if (board.side_to_move == .white) white_value - black_value else black_value - white_value;
}

fn positionEvaluation(piece_board: u64, comptime piece: brd.Piece) i64 {
    const piece_table = switch (piece) {
        .pawn => &pawn_square_table,
        .knight => &knight_square_table,
        .bishop => &bishop_square_table,
        .rook => &rook_square_table,
        .queen => &queen_square_table,
        .king => &king_middlegame_square_table, // TODO: Determine when to use middlegame and endgame table
    };

    var bb = piece_board;
    var sum: i64 = 0;
    while (bb != 0) : (bb &= bb - 1) {
        const square: brd.Square = @intCast(@ctz(bb));
        sum += piece_table[square];
    }
    return sum;
}
