defmodule ThistleTea.Game.Entity.Data.Trade.Offer do
  @moduledoc false
  defstruct items: %{}, money: 0, spell: nil, accepted?: false
end

defmodule ThistleTea.Game.Entity.Data.Trade do
  @moduledoc """
  A two-player trade and the exact item instances each participant offered.
  The seventh slot retains ownership and can receive an item enchantment.
  """
  @enforce_keys [:id, :initiator, :recipient, :offers, :modified_at]
  defstruct @enforce_keys ++ [phase: :requested]
end

defmodule ThistleTea.Game.Entity.Data.Trade.Exchange do
  @moduledoc false
  @enforce_keys [:id, :changes, :outgoing]
  defstruct @enforce_keys
end

defmodule ThistleTea.Game.Entity.Data.Trade.Prepare do
  @moduledoc false
  @enforce_keys [:id, :coordinator]
  defstruct @enforce_keys
end

defmodule ThistleTea.Game.Entity.Data.Trade.Decision do
  @moduledoc false
  @enforce_keys [:id]
  defstruct @enforce_keys
end

defmodule ThistleTea.Game.Entity.Data.Trade.Receipt do
  @moduledoc false
  @enforce_keys [:id, :guid, :changes, :outgoing, :old_counts]
  defstruct @enforce_keys
end
