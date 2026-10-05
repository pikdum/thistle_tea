defmodule ThistleTea.Game.Core.Battleground.AlteracValley.BeaconTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Battleground.AlteracValley.Beacon
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.GameObject
  alias ThistleTea.Game.Core.Entity.GameObjectTemplate
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Test.Unique

  describe "prepare/2" do
    test "all beacons clear caster ownership and publish the source faction and level" do
      for {entry, team, _attacker} <- beacons() do
        object = object(entry)
        prepared = Beacon.prepare(object, -60_000)
        assert prepared.internal.beacon == %Beacon{team: team, ready_at: 0}
        assert prepared.game_object.level == 0
        assert prepared.game_object.created_by == nil
        assert prepared.game_object.faction == if(team == :alliance, do: 83, else: 84)
        assert prepared.internal.summon.owner_guid == nil
        assert prepared.internal.summon.owner_pid == nil
        assert prepared.internal.summon.despawn_in_ms == nil
      end
    end

    test "ordinary objects and objects outside an Alterac copy stay unchanged" do
      for object <- [object(Unique.integer()), put_in(object(178_545).internal.world, WorldRef.open(30))] do
        assert Beacon.prepare(object, 0) == object
      end
    end
  end

  describe "summon/2" do
    test "a waiting beacon summons exactly once after sixty seconds at thirty yards above it" do
      for {entry, _team, attacker} <- beacons() do
        object = Beacon.prepare(object(entry), 100)
        assert Beacon.summon(object, 60_099) == object
        summoned = Beacon.summon(object, 60_100)
        assert summoned.internal.beacon.status == :summoned
        assert [%Effects.SummonCreature{summon: spawn, steps: []}] = summoned.internal.events
        assert spawn.entry == attacker
        assert spawn.position == {1.0, 2.0, 33.0, 0.0}
        assert spawn.despawn_type == 5
        assert spawn.despawn_delay_ms == 10_000
        assert Beacon.summon(summoned, 120_000) == summoned
        assert {:error, ^summoned} = Beacon.disable(summoned, :horde, 60_101)
      end
    end
  end

  describe "disable/3" do
    test "only enemies can disable a waiting beacon before its deadline" do
      for {entry, team, _attacker} <- beacons() do
        object = Beacon.prepare(object(entry), 0)
        enemy = if team == :alliance, do: :horde, else: :alliance
        assert {:error, ^object} = Beacon.disable(object, team, 1)
        assert {:error, ^object} = Beacon.disable(object, nil, 1)
        assert {:error, ^object} = Beacon.disable(object, enemy, 60_000)
        assert {:ok, disabled} = Beacon.disable(object, enemy, 59_999)
        assert disabled.internal.beacon.status == :disabled
        assert Beacon.summon(disabled, 60_000) == disabled
        assert disabled.internal.events == []
        assert {:error, ^disabled} = Beacon.disable(disabled, enemy, 59_999)
      end
    end
  end

  defp object(entry) do
    GameObject.build_summoned(
      %GameObjectTemplate{entry: entry, type: 10, size: 1.0, flags: 0, faction: 0, data: [99]},
      WorldRef.instance(30, Unique.integer()),
      {1.0, 2.0, 3.0, 0.0},
      summoned_by: Unique.integer(),
      owner_pid: self(),
      level: 60,
      despawn_in_ms: 8_000
    )
  end

  defp beacons do
    [
      {178_545, :horde, 13_178},
      {178_547, :horde, 13_178},
      {178_549, :horde, 13_178},
      {178_724, :alliance, 13_161},
      {178_725, :alliance, 13_161},
      {178_726, :alliance, 13_161}
    ]
  end
end
