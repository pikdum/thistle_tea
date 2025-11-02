defmodule ThistleTea.Game.Entity.Data.Component.Container do
  use ThistleTea.Game.Entity.UpdateMask,
    num_slots: {0x0030, 1, :int},
    slots: {0x0032, 72, :guid}
end
