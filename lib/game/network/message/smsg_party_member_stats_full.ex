defmodule ThistleTea.Game.Network.Message.SmsgPartyMemberStatsFull do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_PARTY_MEMBER_STATS_FULL

  alias ThistleTea.Game.Party.MemberStats

  defstruct [:guid, :status, :cur_hp, :max_hp, :power_type, :cur_power, :max_power, :level, :zone]

  @impl ServerMessage
  def to_binary(%__MODULE__{} = msg) do
    MemberStats.encode(Map.from_struct(msg))
  end
end
