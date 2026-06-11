defmodule ThistleTea.Game.Network.Message.SmsgQuestgiverQuestComplete do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_QUESTGIVER_QUEST_COMPLETE

  alias ThistleTea.Game.Entity.Data.Quest

  defstruct [:quest, xp: 0]

  @impl ServerMessage
  def to_binary(%__MODULE__{quest: %Quest{} = q, xp: xp}) do
    <<q.id::little-size(32), 3::little-size(32), xp::little-size(32), q.reward_money::little-signed-size(32),
      length(q.reward_items)::little-size(32)>> <>
      Enum.map_join(q.reward_items, fn {item_id, count} ->
        <<item_id::little-size(32), count::little-size(32)>>
      end)
  end
end
