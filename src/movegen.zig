const std = @import("std");
const fen = @import("fen.zig");
const move = @import("movegen/move.zig");
const pawn = @import("movegen/pawn.zig");
const leaper = @import("movegen/leaper.zig");
const slider = @import("movegen/slider.zig");

pub const MoveFlags = move.MoveFlags;
pub const Move = move.Move;
pub const MoveList = move.MoveList;
pub const IllegalMove = move.IllegalMove;
pub const GameEnd = move.GameEnd;
pub const addPromotionMoves = move.addPromotionMoves;
pub const addMovesFromTargets = move.addMovesFromTargets;
pub const generateMoves = move.generateMoves;
pub const legalMoves = move.legalMoves;
pub const hasLegalMove = move.hasLegalMove;
pub const isInCheck = move.isInCheck;
pub const isCheckmate = move.isCheckmate;
pub const isStalemate = move.isStalemate;
pub const gameEnd = move.gameEnd;
pub const makeMove = move.makeMove;
pub const makeMoveIfLegal = move.makeMoveIfLegal;
pub const perft = move.perft;

pub const generatePawnPushes = pawn.generatePawnPushes;
pub const singlePawnPushesToMoves = pawn.singlePawnPushesToMoves;
pub const doublePawnPushesToMoves = pawn.doublePawnPushesToMoves;
pub const pawnCapturesToMoves = pawn.pawnCapturesToMoves;

pub const leaperMoves = leaper.leaperMoves;
pub const sliderMoves = slider.sliderMoves;

test "movegen facade exposes legal move and game state queries" {
    const start = try fen.parseFen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");
    var list = MoveList{};
    legalMoves(&start, &list);

    try std.testing.expectEqual(@as(u16, 20), list.count);
    try std.testing.expect(hasLegalMove(&start));
    try std.testing.expect(!isInCheck(&start, .white));
    try std.testing.expect(!isCheckmate(&start));
    try std.testing.expect(!isStalemate(&start));
    try std.testing.expectEqual(@as(?GameEnd, null), gameEnd(&start));
}
