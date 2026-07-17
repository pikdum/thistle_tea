defmodule ThistleTea.Game.Entity.Data.Component.Object do
  @moduledoc false
  use ThistleTea.Game.Entity.UpdateMask,
    guid: {0x0000, 2, :guid},
    type: {0x0002, 1, :int},
    entry: {0x0003, 1, :int},
    scale_x: {0x0004, 1, :float},
    base_scale_x: {:virtual, 1.0}
end
