defmodule ThistleTea.Game.Player.GameObjects do
  @moduledoc """
  Player-side game object interaction: routing CMSG_GAMEOBJ_USE and the
  open-lock spell completion to the chest loot window, and everything else
  to the object's own use handler.
  """
  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.GameObjectTemplate
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.Player.Fishing
  alias ThistleTea.Game.Player.Looting
  alias ThistleTea.Game.Player.Quests
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.GameObjectTemplate, as: GameObjectTemplateLoader
  alias ThistleTea.Game.World.System.Instance, as: InstanceSystem

  require Logger

  @go_type_chest 3
  @go_type_chair 7

  def use_object(%{character: %Character{} = character} = state, guid) do
    Logger.info("CMSG_GAMEOBJ_USE: entry #{Guid.entry(guid)} chest?=#{chest?(guid)}")
    state = Quests.credit_entity_interaction(state, guid)

    cond do
      fishing_bobber?(guid) ->
        Fishing.catch_fish(state, guid)

      chest?(guid) ->
        open_chest(state, guid)

      chair?(guid) ->
        sit_on_chair(state, guid)

      true ->
        InstanceSystem.game_object_used(character.internal.world, Guid.entry(guid))
        Entity.use_game_object(guid, state.guid, character.unit.level)
        state
    end
  end

  defp fishing_bobber?(guid) do
    Guid.entity_type(guid) == :game_object and
      match?(%GameObjectTemplate{type: 17}, GameObjectTemplateLoader.get(Guid.entry(guid)))
  end

  defp chair?(guid) do
    Guid.entity_type(guid) == :game_object and
      match?(%GameObjectTemplate{type: @go_type_chair}, GameObjectTemplateLoader.get(Guid.entry(guid)))
  end

  defp sit_on_chair(%{character: %Character{internal: %{world: world}} = character} = state, guid) do
    with {^world, x, y, z} <- World.position(character),
         {:ok, position, stand_state} <- Entity.call(guid, {:chair_seat, world, {x, y, z}}) do
      character =
        character
        |> then(fn character -> %{character | unit: %{character.unit | stand_state: stand_state}} end)
        |> Effects.enqueue([Effects.teleport(position), Effects.stand_state(stand_state)])
        |> EventSink.emit_pending()

      %UpdateObject{update_type: :values, object_type: :player}
      |> struct(Map.from_struct(character))
      |> World.broadcast_packet(character, include_self?: false)

      %{state | character: character}
    else
      _error ->
        state
    end
  end

  def open_chest(state, guid), do: Looting.open(state, guid)

  def chest?(guid) do
    Guid.entity_type(guid) == :game_object and
      match?(%GameObjectTemplate{type: @go_type_chest}, GameObjectTemplateLoader.get(Guid.entry(guid)))
  end
end
