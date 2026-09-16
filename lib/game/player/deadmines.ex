defmodule ThistleTea.Game.Player.Deadmines do
  @moduledoc """
  Player boundary for the Defias cannon: validates the live target and plans
  gunpowder consumption before asking the dungeon owner to start the breach.
  """

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Inventory.Batch
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Math
  alias ThistleTea.Game.Network.InventoryUpdate
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.InstanceData
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.System.Instance, as: InstanceSystem
  alias ThistleTea.Game.WorldRef

  def cannon?(guid) when is_integer(guid), do: Guid.entity_type(guid) == :game_object and Guid.entry(guid) == 16_398
  def cannon?(_guid), do: false

  def validate_cast(state, %Spell{id: 6_250}, %Target{} = targets, item_guid) do
    with :ok <- validate_target(state, Target.object_guid(targets)),
         %Item{object: %{entry: 5_397}} <- ItemStore.get(item_guid),
         {_bag, _slot} <- Inventory.find_position(state.character.player, item_guid, &ItemStore.get/1) do
      :ok
    else
      {:error, _reason} = error -> error
      _ -> {:error, :item_not_found}
    end
  end

  def validate_cast(_state, _spell, _targets, _item_guid), do: :ok

  def fire(state, guid, consume_powder? \\ true) do
    with :ok <- validate_target(state, guid),
         {:ok, change_set} <- plan_powder(state, consume_powder?),
         {:ok, 1} <- InstanceSystem.command(state.character.internal.world, 1, 1, :raw) do
      if change_set, do: InventoryUpdate.apply(state, {:ok, change_set}), else: state
    else
      _ -> state
    end
  end

  def validate_target(%{character: %Character{} = character}, guid) do
    with true <- cannon?(guid),
         false <- Core.dead?(character),
         {%WorldRef{map_id: 36, instance_id: instance_id} = world, x, y, z} when is_integer(instance_id) <-
           World.position(character),
         {^world, tx, ty, tz} <- World.position(guid),
         true <- Math.distance({x, y, z}, {tx, ty, tz}) <= 10.0,
         %{fields: %{1 => {:ok, 0}}} <- InstanceData.read(world, [1]) do
      :ok
    else
      _ -> {:error, :bad_targets}
    end
  end

  defp plan_powder(state, true) do
    state.character.player
    |> Batch.new()
    |> Batch.remove(5_397, 1)
    |> Inventory.plan(&ItemStore.get/1)
  end

  defp plan_powder(_state, false), do: {:ok, nil}
end
