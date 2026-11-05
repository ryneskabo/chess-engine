const move = @import("movegen/move.zig");
const pawn = @import("movegen/pawn.zig");
const leaper = @import("movegen/leaper.zig");
const slider = @import("movegen/slider.zig");

pub const MoveFlags = move.MoveFlags;
pub const Move = move.Move;
pub const MoveList = move.MoveList;
pub const addMovesFromTargets = move.addMovesFromTargets;
pub const generateMoves = move.generateMoves;
pub const makeMove = move.makeMove;
pub const makeMoveIfLegal = move.makeMoveIfLegal;
pub const perft = move.perft;

pub const generatePawnPushes = pawn.generatePawnPushes;
pub const singlePawnPushesToMoves = pawn.singlePawnPushesToMoves;
pub const doublePawnPushesToMoves = pawn.doublePawnPushesToMoves;
pub const pawnCapturesToMoves = pawn.pawnCapturesToMoves;

pub const leaperMoves = leaper.leaperMoves;
pub const sliderMoves = slider.sliderMoves;
