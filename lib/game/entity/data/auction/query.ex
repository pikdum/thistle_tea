defmodule ThistleTea.Game.Entity.Data.Auction.Query do
  @moduledoc false

  defstruct offset: 0,
            name: "",
            level_min: 0,
            level_max: 0,
            inventory_type: 0xFFFFFFFF,
            class: 0xFFFFFFFF,
            subclass: 0xFFFFFFFF,
            quality: 0xFFFFFFFF,
            usable?: false
end
