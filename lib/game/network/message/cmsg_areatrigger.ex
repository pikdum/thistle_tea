defmodule ThistleTea.Game.Network.Message.CmsgAreatrigger do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_AREATRIGGER

  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Player.Quests
  alias ThistleTea.Game.World.Loader.AreaTrigger, as: AreaTriggerLoader

  @trigger_range_delta 5.0

  defstruct [:trigger_id]

  @impl ClientMessage
  def handle(%__MODULE__{trigger_id: trigger_id}, %{ready: true, character: %Character{} = c} = state) do
    {x, y, z, _o} = c.movement_block.position

    with %{} = trigger <- AreaTriggerLoader.get(trigger_id),
         true <- AreaTriggerLoader.inside?(trigger, c.internal.map, {x, y, z}, @trigger_range_delta) do
      handle_trigger(state, c, trigger_id)
    else
      _out_of_range -> state
    end
  end

  def handle(_message, state), do: state

  defp handle_trigger(state, c, trigger_id) do
    quest_id = AreaTriggerLoader.quest_for(trigger_id)

    if is_integer(quest_id) and Death.alive?(c) do
      Quests.explore_area(state, quest_id)
    else
      state
    end
  end

  @impl ClientMessage
  def from_binary(payload) do
    <<trigger_id::little-size(32)>> = payload

    %__MODULE__{
      trigger_id: trigger_id
    }
  end
end
