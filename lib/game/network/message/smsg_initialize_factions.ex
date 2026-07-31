defmodule ThistleTea.Game.Network.Message.SmsgInitializeFactions do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_INITIALIZE_FACTIONS

  defstruct factions: []

  @impl ServerMessage
  def to_binary(%__MODULE__{factions: factions}) when length(factions) == 64 do
    entries =
      Enum.map_join(factions, fn {flags, standing} ->
        <<flags, standing::little-signed-size(32)>>
      end)

    <<64::little-size(32)>> <> entries
  end
end
