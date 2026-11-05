pub const board = @import("board.zig");
pub const fen = @import("fen.zig");
pub const attacks = @import("attacks.zig");
pub const movegen = @import("movegen.zig");

test {
    _ = @import("board.zig");
    _ = @import("fen.zig");
    _ = @import("attacks.zig");
    _ = @import("movegen.zig");
    // Import test-bearing submodules directly; facade imports alone do not
    // make their tests part of the root test binary.
    _ = @import("attacks/leapers.zig");
    _ = @import("attacks/sliders.zig");
    _ = @import("movegen/move.zig");
    _ = @import("movegen/pawn.zig");
    _ = @import("movegen/leaper.zig");
    _ = @import("movegen/slider.zig");
    _ = @import("attacks/query.zig");
}
