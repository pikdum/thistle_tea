defmodule ThistleTea.Game.World do
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.World.SpatialHash

  def nearby_players(
        %{internal: %Internal{map: map}, movement_block: %MovementBlock{position: {x, y, z, _o}}},
        range \\ 250
      ) do
    SpatialHash.query(:players, map, x, y, z, range)
  end

  def broadcast_packet(packet, entity, opts \\ [])

  def broadcast_packet(packets, entity, opts) when is_list(packets) do
    Enum.each(packets, fn packet -> broadcast_packet(packet, entity, opts) end)
  end

  def broadcast_packet(packet, entity, opts) do
    range = Keyword.get(opts, :range, 250)
    include_self? = Keyword.get(opts, :include_self?, true)

    nearby_players(entity, range)
    |> Enum.each(fn {_guid, pid, _distance} ->
      if include_self? or pid != self() do
        Network.send_packet(packet, pid)
      end
    end)
  end
end
