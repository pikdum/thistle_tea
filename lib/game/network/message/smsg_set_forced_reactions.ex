defmodule ThistleTea.Game.Network.Message.SmsgSetForcedReactions do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_SET_FORCED_REACTIONS

  defstruct reactions: []

  @impl ServerMessage
  def to_binary(%__MODULE__{reactions: reactions}) do
    entries =
      Enum.map_join(reactions, fn {faction_id, rank} ->
        <<faction_id::little-size(32), rank::little-size(32)>>
      end)

    <<length(reactions)::little-size(32)>> <> entries
  end
end
