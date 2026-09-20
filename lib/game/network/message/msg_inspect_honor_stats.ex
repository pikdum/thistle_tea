defmodule ThistleTea.Game.Network.Message.MsgInspectHonorStats do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :MSG_INSPECT_HONOR_STATS

  alias ThistleTea.Game.Entity.Data.Component.Player

  defstruct [:guid, :player]

  @impl ServerMessage
  def to_binary(%__MODULE__{guid: guid, player: %Player{} = player}) do
    <<guid::little-size(64), player.highest_honor_rank::size(8), player.session_kills::little-size(32),
      player.yesterday_kills::little-size(16), 0::little-size(16), player.last_week_kills::little-size(16),
      0::little-size(16), player.this_week_kills::little-size(16), 0::little-size(16),
      player.lifetime_honorable_kills::little-size(32), player.lifetime_dishonorable_kills::little-size(32),
      player.yesterday_contribution::little-size(32), player.last_week_contribution::little-size(32),
      player.this_week_contribution::little-size(32), player.last_week_rank::little-size(32),
      player.honor_rank_bar::size(8)>>
  end
end
