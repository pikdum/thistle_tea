defmodule ThistleTea.Game.Network.Message.CmsgLearnTalent do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_LEARN_TALENT

  alias ThistleTea.Game.Player.Talents

  defstruct [:talent_id, :requested_rank]

  @impl ClientMessage
  def handle(%__MODULE__{talent_id: talent_id, requested_rank: requested_rank}, %{ready: true} = state) do
    Talents.learn(state, talent_id, requested_rank)
  end

  def handle(_message, state), do: state

  @impl ClientMessage
  def from_binary(payload) do
    <<talent_id::little-size(32), requested_rank::little-size(32)>> = payload

    %__MODULE__{
      talent_id: talent_id,
      requested_rank: requested_rank
    }
  end
end
