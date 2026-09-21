defmodule ThistleTea.Game.Network.Message.MsgQuestPushResult do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :MSG_QUEST_PUSH_RESULT

  defstruct [:guid, :result]

  def code(:sharing), do: 0
  def code(:cannot_take), do: 1
  def code(:accepted), do: 2
  def code(:declined), do: 3
  def code(:too_far), do: 4
  def code(:busy), do: 5
  def code(:log_full), do: 6
  def code(:have_quest), do: 7
  def code(:finished), do: 8
  def code(result) when result in 0..8, do: result

  @impl ServerMessage
  def to_binary(%__MODULE__{guid: guid, result: result}), do: <<guid::little-size(64), result::little-size(8)>>
end
