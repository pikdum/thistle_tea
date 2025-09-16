defmodule ThistleTea.Game.Entities.Data.Object do
  use ThistleTea.Game.FieldStruct,
    guid: {0x0000, 2, :guid},
    type: {0x0002, 1, :int},
    entry: {0x0003, 1, :int},
    scale_x: {0x0004, 1, :float}
end
