defmodule ThistleTea.Game.World.System.LocalDefenseTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.Network.Message.SmsgZoneUnderAttack
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.World.System.LocalDefense
  alias ThistleTea.Test.Unique

  @human 1
  @orc 2

  describe "alert/4" do
    setup [:server, :players]

    test "warns the defending team on the map once per cooldown", %{server: server, world: world} = context do
      %{defender: defender, attacker: attacker, elsewhere: elsewhere, relays: relays} = context
      area = Unique.integer()
      other_area = Unique.integer()

      LocalDefense.alert(world, area, :horde, server)
      LocalDefense.alert(world, area, :horde, server)
      LocalDefense.alert(world, other_area, :alliance, server)
      :sys.get_state(server)
      Enum.each(relays, &sync/1)

      assert_received {^defender, %SmsgZoneUnderAttack{area_id: ^area}}
      assert_received {^attacker, %SmsgZoneUnderAttack{area_id: ^other_area}}
      refute_received {^defender, %SmsgZoneUnderAttack{}}
      refute_received {^attacker, %SmsgZoneUnderAttack{}}
      refute_received {^elsewhere, %SmsgZoneUnderAttack{}}
    end
  end

  defp server(_context) do
    server = :"local_defense_#{Unique.integer()}"
    start_supervised!({LocalDefense, name: server})
    %{server: server}
  end

  defp players(_context) do
    map_id = Unique.integer()
    [defender, attacker, elsewhere] = guids = Enum.map(1..3, fn _ -> Unique.integer() end)

    relays =
      for {guid, race, map} <- [
            {defender, @human, map_id},
            {attacker, @orc, map_id},
            {elsewhere, @human, Unique.integer()}
          ] do
        Metadata.put(guid, %{race: race})
        SpatialHash.update(:players, guid, map, 1.0, 2.0, 3.0)
        relay(guid)
      end

    on_exit(fn ->
      for guid <- guids do
        Metadata.delete(guid)
        SpatialHash.remove(:players, guid)
      end
    end)

    %{world: WorldRef.open(map_id), defender: defender, attacker: attacker, elsewhere: elsewhere, relays: relays}
  end

  defp relay(guid) do
    test = self()

    pid =
      spawn_link(fn ->
        {:ok, _} = Entity.register(guid)
        send(test, {:registered, guid})
        forward(test, guid)
      end)

    assert_receive {:registered, ^guid}
    pid
  end

  defp forward(test, guid) do
    receive do
      {:"$gen_cast", {:send_packet, packet}} -> send(test, {guid, packet})
      {:sync, from} -> send(from, {:synced, self()})
    end

    forward(test, guid)
  end

  defp sync(relay) do
    send(relay, {:sync, self()})
    assert_receive {:synced, ^relay}, 1_000
  end
end
