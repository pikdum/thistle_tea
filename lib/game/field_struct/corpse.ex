defmodule ThistleTea.Game.FieldStruct.Corpse do
  use ThistleTea.Game.FieldStruct,
    owner: {0x0006, 2, :guid},
    facing: {0x0008, 1, :float},
    pos_x: {0x0009, 1, :float},
    pos_y: {0x000A, 1, :float},
    pos_z: {0x000B, 1, :float},
    display_id: {0x000C, 1, :int},
    items: {0x000D, 19, :int},
    bytes_1: {0x0020, 1, :bytes},
    bytes_2: {0x0021, 1, :bytes},
    guild_id: {0x0022, 1, :int},
    flags: {0x0023, 1, :int},
    dynamic_flags: {0x0024, 1, :int}
end
