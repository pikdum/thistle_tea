defmodule ThistleTea.Game.Network.Message.SmsgQuestgiverQuestInvalid do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_QUESTGIVER_QUEST_INVALID

  defstruct [:reason]

  @impl ServerMessage
  def to_binary(%__MODULE__{reason: reason}) do
    <<reason::little-size(32)>>
  end
end
