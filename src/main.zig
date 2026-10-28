const std = @import("std");
const Io = std.Io;

const fen = @import("fen.zig");
const brd = @import("board.zig");

pub fn main() !void {
    const board: brd.Board = try fen.parseFen("rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1");

    std.debug.print("castling rights: {b}, halfmove clock: {d}", .{ board.castling_rights, board.halfmove_clock });
}
