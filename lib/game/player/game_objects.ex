defmodule ThistleTea.Game.Player.GameObjects do
  @moduledoc """
  Player-side game object interaction: routing CMSG_GAMEOBJ_USE and the
  open-lock spell completion to the chest loot window, and everything else
  to the object's own use handler.
  """
  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.GameObjectTemplate
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Loot
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.Fishing
  alias ThistleTea.Game.Player.Quests
  alias ThistleTea.Game.World.Loader.GameObjectTemplate, as: GameObjectTemplateLoader

  require Logger

  @go_type_chest 3

  def use_object(%{character: %Character{} = character} = state, guid) do
    Logger.info("CMSG_GAMEOBJ_USE: entry #{Guid.entry(guid)} chest?=#{chest?(guid)}")

    cond do
      fishing_bobber?(guid) ->
        Fishing.catch_fish(state, guid)

      chest?(guid) ->
        open_chest(state, guid)

      true ->
        Entity.use_game_object(guid, state.guid, character.unit.level)
        state
    end
  end

  defp fishing_bobber?(guid) do
    Guid.entity_type(guid) == :game_object and
      match?(%GameObjectTemplate{type: 17}, GameObjectTemplateLoader.get(Guid.entry(guid)))
  end

  def open_chest(%{character: %Character{} = c} = state, guid) do
    with true <- chest?(guid),
         false <- Core.dead?(c),
         {:ok, %Loot{} = loot} <- Entity.call(guid, {:loot_view, state.guid}) do
      loot = Quests.filter_loot(loot, c)
      Logger.info("Chest loot: entry #{Guid.entry(guid)} items=#{length(loot.items)} gold=#{loot.gold}")
      Network.send_packet(%Message.SmsgLootResponse{guid: guid, loot: loot})
      %{state | loot_guid: guid}
    else
      other ->
        Logger.info("Chest open failed: entry #{Guid.entry(guid)} reason=#{inspect(other)}")
        Network.send_packet(%Message.SmsgLootReleaseResponse{guid: guid})
        state
    end
  end

  def chest?(guid) do
    Guid.entity_type(guid) == :game_object and
      match?(%GameObjectTemplate{type: @go_type_chest}, GameObjectTemplateLoader.get(Guid.entry(guid)))
  end
end
