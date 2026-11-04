const std = @import("std");
const brd = @import("../board.zig");
const leapers = @import("leapers.zig");
const sliders = @import("sliders.zig");

const Board = brd.Board;
const Square = brd.Square;
const Color = brd.Color;
const Piece = brd.Piece;

pub fn isSquareAttacked(board: *const Board, square: Square, by_color: Color) bool {
    return isSquareAttackedByPawn(board, square, by_color) or
        isSquareAttackedByKnight(board, square, by_color) or
        isSquareAttackedBySlider(board, square, by_color) or
        isSquareAttackedByKing(board, square, by_color);
}

fn isSquareAttackedByPawn(board: *const Board, square: Square, by_color: Color) bool {
    // pawn attacks the same squares that an enemy would attack back from
    return leapers.pawn_attacks[@backingInt(by_color.opposite())][square] & board.getBoard(by_color, .pawn) != 0;
}

fn isSquareAttackedByKnight(board: *const Board, square: Square, by_color: Color) bool {
    return leapers.knight_attacks[square] & board.getBoard(by_color, .knight) != 0;
}

fn isSquareAttackedBySlider(board: *const Board, square: Square, by_color: Color) bool {
    const occupancy = board.occupancy[@backingInt(Color.white)] | board.occupancy[@backingInt(Color.black)];
    const bishops = board.getBoard(by_color, .bishop);
    const rooks = board.getBoard(by_color, .rook);
    const queens = board.getBoard(by_color, .queen);

    return sliders.bishopAttacks(square, occupancy) & (bishops | queens) != 0 or sliders.rookAttacks(square, occupancy) & (rooks | queens) != 0;
}

fn isSquareAttackedByKing(board: *const Board, square: Square, by_color: Color) bool {
    return leapers.king_attacks[square] & board.getBoard(by_color, .king) != 0;
}

fn expectAttacked(board: *const Board, square: Square, by_color: Color) !void {
    try std.testing.expect(isSquareAttacked(board, square, by_color));
}

fn expectNotAttacked(board: *const Board, square: Square, by_color: Color) !void {
    try std.testing.expect(!isSquareAttacked(board, square, by_color));
}

/// Reference implementation that walks every attacking piece instead of using
/// reverse attack lookups. Slider attacks still use the tested ray functions.
fn bruteForceIsSquareAttacked(board: *const Board, square: Square, by_color: Color) bool {
    const occupancy = board.occupancy[@backingInt(Color.white)] | board.occupancy[@backingInt(Color.black)];

    for (std.enums.values(Piece)) |piece| {
        var pieces = board.getBoard(by_color, piece);
        while (pieces != 0) : (pieces &= pieces - 1) {
            const from: Square = @intCast(@ctz(pieces));
            const attacks = switch (piece) {
                .pawn => leapers.pawn_attacks[@backingInt(by_color)][from],
                .knight => leapers.knight_attacks[from],
                .bishop => sliders.bishopAttacks(from, occupancy),
                .rook => sliders.rookAttacks(from, occupancy),
                .queen => sliders.queenAttacks(from, occupancy),
                .king => leapers.king_attacks[from],
            };

            if (attacks & brd.squareBit(square) != 0) return true;
        }
    }

    return false;
}

test "empty board has no attacked squares" {
    const board = brd.empty;

    for (0..64) |sq| {
        try expectNotAttacked(&board, @intCast(sq), .white);
        try expectNotAttacked(&board, @intCast(sq), .black);
    }
}

test "pawns attack diagonally forward only" {
    var white_board = brd.empty;
    white_board.setPiece(.white, .pawn, 27); // d4
    white_board.setPiece(.white, .pawn, 8); // a2

    try expectAttacked(&white_board, 34, .white); // c5
    try expectAttacked(&white_board, 36, .white); // e5
    try expectNotAttacked(&white_board, 35, .white); // d5
    try expectNotAttacked(&white_board, 26, .white); // c4
    try expectNotAttacked(&white_board, 27, .white); // own square
    try expectAttacked(&white_board, 17, .white); // a2 -> b3
    try expectNotAttacked(&white_board, 23, .white); // no wrap to h3
    try expectNotAttacked(&white_board, 16, .white); // a2 does not attack a3

    try expectNotAttacked(&white_board, 34, .black);
    try expectNotAttacked(&white_board, 36, .black);

    var black_board = brd.empty;
    black_board.setPiece(.black, .pawn, 35); // d5
    black_board.setPiece(.black, .pawn, 48); // a7

    try expectAttacked(&black_board, 26, .black); // c4
    try expectAttacked(&black_board, 28, .black); // e4
    try expectNotAttacked(&black_board, 27, .black); // d4
    try expectNotAttacked(&black_board, 36, .black); // e5
    try expectAttacked(&black_board, 41, .black); // a7 -> b6
    try expectNotAttacked(&black_board, 47, .black); // no wrap to h6
    try expectNotAttacked(&black_board, 40, .black); // a7 does not attack a6

    try expectNotAttacked(&black_board, 26, .white);
    try expectNotAttacked(&black_board, 28, .white);
}

test "knights attack every L-shaped destination" {
    var board = brd.empty;
    board.setPiece(.white, .knight, 28); // e4

    const targets = [_]Square{
        43, // d6
        45, // f6
        34, // c5
        38, // g5
        18, // c3
        22, // g3
        11, // d2
        13, // f2
    };

    for (targets) |target| {
        try expectAttacked(&board, target, .white);
        try expectNotAttacked(&board, target, .black);
    }

    try expectNotAttacked(&board, 28, .white); // own square
    try expectNotAttacked(&board, 36, .white); // not a knight move

    var black_board = brd.empty;
    black_board.setPiece(.black, .knight, 35); // d5

    try expectAttacked(&black_board, 18, .black); // c3
    try expectAttacked(&black_board, 41, .black); // b6
    try expectAttacked(&black_board, 50, .black); // c7
    try expectNotAttacked(&black_board, 18, .white);
}

test "kings attack adjacent squares only" {
    var board = brd.empty;
    board.setPiece(.white, .king, 28); // e4

    const adjacent = [_]Square{
        35, // d5
        36, // e5
        37, // f5
        27, // d4
        29, // f4
        19, // d3
        20, // e3
        21, // f3
    };

    for (adjacent) |target| {
        try expectAttacked(&board, target, .white);
        try expectNotAttacked(&board, target, .black);
    }

    try expectNotAttacked(&board, 28, .white); // own square
    try expectNotAttacked(&board, 44, .white); // two squares away
    try expectNotAttacked(&board, 34, .white); // two files away

    var black_board = brd.empty;
    black_board.setPiece(.black, .king, 0); // a1

    try expectAttacked(&black_board, 1, .black); // b1
    try expectAttacked(&black_board, 8, .black); // a2
    try expectAttacked(&black_board, 9, .black); // b2
    try expectNotAttacked(&black_board, 2, .black); // c1
    try expectNotAttacked(&black_board, 1, .white);
}

test "bishops attack diagonals and stop at the first blocker" {
    const blocker_colors = [_]Color{ .white, .black };

    for (blocker_colors) |blocker_color| {
        var board = brd.empty;
        board.setPiece(.white, .bishop, 0); // a1
        board.setPiece(blocker_color, .knight, 18); // c3

        try expectAttacked(&board, 9, .white); // b2
        try expectAttacked(&board, 18, .white); // c3, the blocker itself
        try expectNotAttacked(&board, 27, .white); // d4, beyond c3
        try expectNotAttacked(&board, 56, .white); // a8, beyond c3
        try expectNotAttacked(&board, 17, .white); // b3, off the diagonal
    }

    var corner_board = brd.empty;
    corner_board.setPiece(.white, .bishop, 7); // h1

    try expectAttacked(&corner_board, 14, .white); // g2
    try expectAttacked(&corner_board, 56, .white); // a8
    try expectNotAttacked(&corner_board, 15, .white); // h2, off the diagonal
}

test "rooks attack ranks and files and stop at the first blocker" {
    var board = brd.empty;
    board.setPiece(.white, .rook, 28); // e4
    board.setPiece(.white, .pawn, 44); // e6, friendly blocker
    board.setPiece(.black, .pawn, 26); // c4, enemy blocker

    try expectAttacked(&board, 36, .white); // e5
    try expectAttacked(&board, 44, .white); // e6, blocker itself
    try expectNotAttacked(&board, 52, .white); // e7, beyond e6
    try expectNotAttacked(&board, 60, .white); // e8, beyond e6

    try expectAttacked(&board, 27, .white); // d4
    try expectAttacked(&board, 26, .white); // c4, blocker itself
    try expectNotAttacked(&board, 25, .white); // b4, beyond c4
    try expectNotAttacked(&board, 24, .white); // a4, beyond c4

    try expectAttacked(&board, 29, .white); // f4
    try expectAttacked(&board, 31, .white); // h4
    try expectAttacked(&board, 20, .white); // e3
    try expectAttacked(&board, 4, .white); // e1

    try expectNotAttacked(&board, 36, .black);
    try expectNotAttacked(&board, 31, .black);
}

test "queens attack ranks, files, and diagonals" {
    var board = brd.empty;
    board.setPiece(.white, .queen, 28); // e4

    const attacked = [_]Square{
        60, // e8, file
        4, // e1, file
        24, // a4, rank
        31, // h4, rank
        37, // f5, NE
        55, // h7, NE
        35, // d5, NW
        56, // a8, NW
        21, // f3, SE
        7, // h1, SE
        19, // d3, SW
        1, // b1, SW
    };

    for (attacked) |target| {
        try expectAttacked(&board, target, .white);
        try expectNotAttacked(&board, target, .black);
    }

    try expectNotAttacked(&board, 28, .white); // own square
    try expectNotAttacked(&board, 43, .white); // d6 is a knight move, not a queen ray

    var blocked_board = brd.empty;
    blocked_board.setPiece(.white, .queen, 28); // e4
    blocked_board.setPiece(.white, .pawn, 44); // e6
    blocked_board.setPiece(.black, .pawn, 14); // g2

    try expectAttacked(&blocked_board, 36, .white); // e5
    try expectAttacked(&blocked_board, 44, .white); // e6, blocker itself
    try expectNotAttacked(&blocked_board, 52, .white); // e7, beyond e6

    try expectAttacked(&blocked_board, 21, .white); // f3
    try expectAttacked(&blocked_board, 14, .white); // g2, blocker itself
    try expectNotAttacked(&blocked_board, 7, .white); // h1, beyond g2

    try expectAttacked(&blocked_board, 31, .white); // h4, still open
    try expectAttacked(&blocked_board, 56, .white); // a8, still open
}

test "the square occupied by an attacker is not attacked by itself" {
    for (std.enums.values(Piece)) |piece| {
        for ([_]Color{ .white, .black }) |color| {
            var board = brd.empty;
            board.setPiece(color, piece, 28); // e4

            try expectNotAttacked(&board, 28, color);
        }
    }
}

test "corner attack patterns stay on the board" {
    var knight_board = brd.empty;
    knight_board.setPiece(.white, .knight, 0); // a1
    try expectAttacked(&knight_board, 17, .white); // b3
    try expectAttacked(&knight_board, 10, .white); // c2
    try expectNotAttacked(&knight_board, 15, .white); // h2, would wrap

    var rook_board = brd.empty;
    rook_board.setPiece(.white, .rook, 7); // h1
    try expectAttacked(&rook_board, 63, .white); // h8
    try expectAttacked(&rook_board, 0, .white); // a1
    try expectAttacked(&rook_board, 6, .white); // g1
    try expectAttacked(&rook_board, 15, .white); // h2
    try expectNotAttacked(&rook_board, 9, .white); // b2, off the rank/file

    var king_board = brd.empty;
    king_board.setPiece(.white, .king, 0); // a1
    try expectAttacked(&king_board, 1, .white); // b1
    try expectAttacked(&king_board, 8, .white); // a2
    try expectAttacked(&king_board, 9, .white); // b2
    try expectNotAttacked(&king_board, 2, .white); // c1
    try expectNotAttacked(&king_board, 16, .white); // a3
}

test "both colors are evaluated independently" {
    var board = brd.empty;
    board.setPiece(.white, .knight, 28); // e4 attacks d6
    board.setPiece(.black, .knight, 35); // d5 attacks b4
    board.setPiece(.white, .queen, 0); // a1
    board.setPiece(.black, .rook, 63); // h8

    try expectAttacked(&board, 43, .white); // d6 by white knight
    try expectNotAttacked(&board, 43, .black);

    try expectAttacked(&board, 25, .black); // b4 by black knight
    try expectNotAttacked(&board, 25, .white);

    try expectAttacked(&board, 36, .white); // e5 by white queen
    try expectNotAttacked(&board, 36, .black);

    try expectAttacked(&board, 55, .black); // h7 by black rook
    try expectNotAttacked(&board, 55, .white);
}

test "isSquareAttacked matches a brute-force reference on random boards (fixed seed)" {
    var prng = std.Random.DefaultPrng.init(0xA77AC_4ED_5EED_1234);
    const random = prng.random();

    var iteration: usize = 0;
    while (iteration < 500) : (iteration += 1) {
        var board = brd.empty;
        var occupied: u64 = 0;

        const piece_count = random.intRangeAtMost(usize, 0, 12);
        var placed: usize = 0;
        while (placed < piece_count) {
            const sq: Square = random.int(Square);
            const bit = brd.squareBit(sq);
            if (occupied & bit != 0) continue;

            occupied |= bit;
            const color: Color = if (random.boolean()) .white else .black;
            const piece: Piece = @fromBackingInt(@intCast(random.uintLessThan(u8, 6)));
            board.setPiece(color, piece, sq);
            placed += 1;
        }

        for (0..64) |sq| {
            for ([_]Color{ .white, .black }) |color| {
                const target: Square = @intCast(sq);
                try std.testing.expectEqual(
                    bruteForceIsSquareAttacked(&board, target, color),
                    isSquareAttacked(&board, target, color),
                );
            }
        }
    }
}
