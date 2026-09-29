defmodule ThistleTea.Game.Core.Loot.Reservation do
  @moduledoc false

  alias ThistleTea.Game.Core.Loot

  @enforce_keys [:token, :slot, :actor_guid, :item, :release_blocked?]
  defstruct [:token, :slot, :actor_guid, :item, :release_blocked?]

  @type t :: %__MODULE__{
          token: reference(),
          slot: non_neg_integer(),
          actor_guid: integer(),
          item: Loot.Item.t(),
          release_blocked?: boolean()
        }
end

defmodule ThistleTea.Game.Core.Loot.Commit do
  @moduledoc false

  @enforce_keys [:token, :actor_guid]
  defstruct [:token, :actor_guid]
end

defmodule ThistleTea.Game.Core.Loot.Release do
  @moduledoc false

  @enforce_keys [:token, :actor_guid]
  defstruct [:token, :actor_guid]
end
