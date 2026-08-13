defmodule ThistleTea.Game.Network.Message.MsgPvpLogData do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :MSG_PVP_LOG_DATA

  defstruct ended?: false, winner: :none, players: []

  @winner %{horde: 0, alliance: 1, none: 2}

  @impl ServerMessage
  def to_binary(%__MODULE__{} = message) do
    status = if message.ended?, do: 1, else: 0
    winner = if message.ended?, do: <<Map.fetch!(@winner, message.winner)::little-size(8)>>, else: <<>>

    players =
      Enum.map_join(message.players, fn player ->
        fields = Enum.map_join(player.fields, &<<&1::little-size(32)>>)

        <<player.guid::little-size(64), player.rank::little-size(32), player.killing_blows::little-size(32),
          player.honorable_kills::little-size(32), player.deaths::little-size(32), player.bonus_honor::little-size(32),
          length(player.fields)::little-size(32)>> <> fields
      end)

    <<status::little-size(8)>> <> winner <> <<length(message.players)::little-size(32)>> <> players
  end
end
