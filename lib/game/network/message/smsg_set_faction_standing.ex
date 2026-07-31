defmodule ThistleTea.Game.Network.Message.SmsgSetFactionStanding do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_SET_FACTION_STANDING

  defstruct standings: []

  @impl ServerMessage
  def to_binary(%__MODULE__{standings: standings}) do
    entries =
      Enum.map_join(standings, fn {index, standing} ->
        <<index::little-size(32), standing::little-signed-size(32)>>
      end)

    <<length(standings)::little-size(32)>> <> entries
  end
end
