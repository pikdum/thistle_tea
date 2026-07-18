defmodule ThistleTea.Game.Entity.Logic.Aura.HolderSync do
  @moduledoc """
  Applies the single aura-holder transition: update the holder source of truth,
  recompute derived unit fields, and emit client spell-modifier differences.
  """
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura.ModifierSync
  alias ThistleTea.Game.Entity.Logic.Aura.UnitSync

  def sync(%{unit: %Unit{auras: previous} = unit} = entity, holders) when is_list(previous) and is_list(holders) do
    entity = %{entity | unit: UnitSync.sync_unit(%{unit | auras: holders})}
    {entity, ModifierSync.events(previous, holders)}
  end

  def sync(%{unit: %Unit{} = unit} = entity, holders) when is_list(holders) do
    entity = %{entity | unit: UnitSync.sync_unit(%{unit | auras: holders})}
    {entity, ModifierSync.events([], holders)}
  end
end
