defmodule ThistleTea.Game.FieldStruct.Container do
  use ThistleTea.Game.FieldStruct,
    num_slots: {0x0030, 1, :int},
    slots: {0x0032, 72, :guid}
end
