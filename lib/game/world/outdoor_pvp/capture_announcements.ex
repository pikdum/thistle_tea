defmodule ThistleTea.Game.World.OutdoorPvp.CaptureAnnouncements do
  @moduledoc "Projects tower transitions into continent defense notices and nearby capture sounds."

  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message.SmsgDefenseMessage
  alias ThistleTea.Game.Network.Message.SmsgPlaySound
  alias ThistleTea.Game.OutdoorPvp.Plaguelands
  alias ThistleTea.Game.OutdoorPvp.Towers
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.BroadcastText
  alias ThistleTea.Game.WorldRef

  def publish(previous, current) do
    Enum.each(Towers.ownership_changes(previous, current), fn
      {id, _before, owner} when owner in [:alliance, :horde] -> defense(Plaguelands.towers()[id].announcements[owner])
      _neutral -> :ok
    end)

    old_counts = Towers.counts(previous)

    Enum.each(Towers.counts(current), fn {team, count} ->
      if count == 4 and old_counts[team] != 4, do: defense(Plaguelands.victory_text(team))
    end)

    Enum.each(Towers.phase_changes(previous, current), fn {id, before, after_phase} ->
      sound(id, Plaguelands.phase_sound(before, after_phase))
    end)
  end

  defp defense(text_id) do
    with %{text: text} <- BroadcastText.get(text_id) do
      packet = %SmsgDefenseMessage{zone_id: 139, text: text}

      WorldRef.open(0)
      |> World.players_in()
      |> Enum.each(&Network.send_packet(packet, &1))
    end
  end

  defp sound(_id, nil), do: :ok

  defp sound(id, sound_id) do
    {x, y, z, _orientation} = Plaguelands.towers()[id].position

    WorldRef.open(0)
    |> World.nearby_players_at({x, y, z}, 250)
    |> Enum.each(fn {guid, _distance} -> Network.send_packet(%SmsgPlaySound{sound_id: sound_id}, guid) end)
  end
end
