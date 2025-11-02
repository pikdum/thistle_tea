defmodule ThistleTea.Game.Entity.Data.Component.Object do
  use ThistleTea.Game.Entity.UpdateMask,
    guid: {0x0000, 2, :guid},
    type: {0x0002, 1, :int},
    entry: {0x0003, 1, :int},
    scale_x: {0x0004, 1, :float}
end
