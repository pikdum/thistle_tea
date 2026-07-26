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

  @enforce_keys [:player]
  defstruct [:player, removals: [], additions: []]

  def new(%Player{} = player), do: %__MODULE__{player: player}

  def remove(%__MODULE__{removals: removals} = batch, entry, count)
      when is_integer(entry) and entry > 0 and is_integer(count) and count > 0 do
    %{batch | removals: [%Removal{entry: entry, count: count} | removals]}
  end

  def add(%__MODULE__{additions: additions} = batch, %Item{} = item) do
    %{batch | additions: [item | additions]}
  end

  def removals(%__MODULE__{removals: removals}), do: Enum.reverse(removals)
  def additions(%__MODULE__{additions: additions}), do: Enum.reverse(additions)
end
