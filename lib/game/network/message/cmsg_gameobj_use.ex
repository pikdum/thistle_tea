defmodule ThistleTea.Game.Network.Message.CmsgGameobjUse do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GAMEOBJ_USE

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.GameObjectTemplate
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Loot
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Player.Quests
  alias ThistleTea.Game.World.Loader.GameObjectTemplate, as: GameObjectTemplateLoader

  @go_type_chest 3

  defstruct [:guid]

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid}, %{ready: true, character: %Character{} = character} = state) do
    if chest?(guid) do
      open_chest(state, guid)
    else
      Entity.use_game_object(guid, state.guid, character.unit.level)
      state
    end
  end

  def handle(_message, state), do: state

  defp chest?(guid) do
    Guid.entity_type(guid) == :game_object and
      match?(%GameObjectTemplate{type: @go_type_chest}, GameObjectTemplateLoader.get(Guid.entry(guid)))
  end

  defp open_chest(%{character: %Character{} = c} = state, guid) do
    with false <- Core.dead?(c),
         {:ok, %Loot{} = loot} <- Entity.call(guid, {:loot_view, state.guid}) do
      Network.send_packet(%Message.SmsgLootResponse{guid: guid, loot: Quests.filter_loot(loot, c)})
      %{state | loot_guid: guid}
    else
      _no_loot ->
        Network.send_packet(%Message.SmsgLootReleaseResponse{guid: guid})
        state
    end
  end

  @impl ClientMessage
  def from_binary(payload) do
    <<guid::little-size(64), _rest::binary>> = payload

    %__MODULE__{
      guid: guid
    }
  end
end
