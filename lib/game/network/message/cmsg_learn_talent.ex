defmodule ThistleTea.Game.Network.Message.CmsgLearnTalent do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_LEARN_TALENT

  defstruct [:talent_id, :requested_rank]

  @impl ClientMessage
  def from_binary(payload) do
    <<talent_id::little-size(32), requested_rank::little-size(32)>> = payload

    %__MODULE__{
      talent_id: talent_id,
      requested_rank: requested_rank
    }
  end
end
