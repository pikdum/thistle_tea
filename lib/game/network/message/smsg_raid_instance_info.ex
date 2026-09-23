defmodule ThistleTea.Game.Network.Message.SmsgRaidInstanceInfo do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_RAID_INSTANCE_INFO

  defstruct raids: []

  @impl ServerMessage
  def to_binary(%__MODULE__{raids: raids}) do
    body =
      for %{map_id: map, instance_id: id, seconds_remaining: seconds} <- raids, into: <<>> do
        <<map::little-size(32), seconds::little-size(32), id::little-size(32)>>
      end

    <<length(raids)::little-size(32), body::binary>>
  end
end
