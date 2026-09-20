defmodule ThistleTea.Game.Entity.Logic.Inventory.Batch do
  @moduledoc """
  A pure inventory transaction request. Removals are planned before additions
  so consumed items can free capacity for the items granted by the same
  gameplay transition.
  """

  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Item

  defmodule Removal do
    @moduledoc false
    @enforce_keys [:entry, :count]
    defstruct [:entry, :count]
  end

  defmodule ItemRemoval do
    @moduledoc false
    @enforce_keys [:guid, :count]
    defstruct [:guid, :count]
  end

  defmodule Relocation do
    @moduledoc false
    @enforce_keys [:guid, :destination]
    defstruct @enforce_keys
  end

  @enforce_keys [:player]
  defstruct [:player, removals: [], relocations: [], additions: [], updates: []]

  def new(%Player{} = player), do: %__MODULE__{player: player}

  def remove(%__MODULE__{removals: removals} = batch, entry, count)
      when is_integer(entry) and entry > 0 and is_integer(count) and count > 0 do
    %{batch | removals: [%Removal{entry: entry, count: count} | removals]}
  end

  def add(%__MODULE__{additions: additions} = batch, %Item{} = item) do
    %{batch | additions: [item | additions]}
  end

  def update(%__MODULE__{updates: updates} = batch, %Item{} = item) do
    %{batch | updates: [item | updates]}
  end

  def remove_item(%__MODULE__{removals: removals} = batch, guid, count)
      when is_integer(guid) and guid > 0 and is_integer(count) and count > 0 do
    %{batch | removals: [%ItemRemoval{guid: guid, count: count} | removals]}
  end

  def removals(%__MODULE__{removals: removals}), do: Enum.reverse(removals)

  def relocate(%__MODULE__{relocations: relocations} = batch, guid, destination)
      when is_integer(guid) and guid > 0 and destination in [:carried, :detached] do
    %{batch | relocations: [%Relocation{guid: guid, destination: destination} | relocations]}
  end

  def relocations(%__MODULE__{relocations: relocations}), do: Enum.reverse(relocations)
  def additions(%__MODULE__{additions: additions}), do: Enum.reverse(additions)
  def updates(%__MODULE__{updates: updates}), do: Enum.reverse(updates)
end
