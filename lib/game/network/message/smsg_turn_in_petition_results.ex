defmodule ThistleTea.Game.Network.Message.SmsgTurnInPetitionResults do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_TURN_IN_PETITION_RESULTS

  defstruct [:result]

  @results %{ok: 0, already_in_guild: 2, need_more: 4}

  @impl ServerMessage
  def to_binary(%__MODULE__{result: result}), do: <<Map.fetch!(@results, result)::little-size(32)>>
end
