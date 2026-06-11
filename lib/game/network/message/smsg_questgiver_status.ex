defmodule ThistleTea.Game.Network.Message.SmsgQuestgiverStatus do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_QUESTGIVER_STATUS

  defstruct [:guid, :status]

  @impl ServerMessage
  def to_binary(%__MODULE__{guid: guid, status: status}) do
    <<guid::little-size(64), status::little-size(32)>>
  end
end
