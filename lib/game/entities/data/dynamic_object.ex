defmodule ThistleTea.Game.Entities.Data.DynamicObject do
  use ThistleTea.Game.FieldStruct,
    caster: {0x0006, 2, :guid},
    bytes: {0x0008, 1, :bytes},
    spell_id: {0x0009, 1, :int},
    radius: {0x000A, 1, :float},
    pos_x: {0x000B, 1, :float},
    pos_y: {0x000C, 1, :float},
    pos_z: {0x000D, 1, :float},
    facing: {0x000E, 1, :float}
end
