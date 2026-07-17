defmodule ThistleTea.Game.Entity.Logic.ThreatTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Entity.Logic.Threat
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World.Metadata

  @mob_guid 100
  @player_a 1
  @player_b 2
  @player_c 3

  defp mob(attrs \\ []) do
    %Mob{
      object: %Object{guid: Keyword.get(attrs, :guid, @mob_guid)},
      unit: %Unit{target: Keyword.get(attrs, :target, 0)},
      internal: %Internal{
        in_combat: Keyword.get(attrs, :in_combat, true),
        threat: Keyword.get(attrs, :threat, %{})
      }
    }
  end

  defp reselect(entity, opts \\ []) do
    opts =
      opts
      |> Keyword.put_new(:valid?, fn _guid -> true end)
      |> Keyword.put_new(:in_melee?, fn _guid -> false end)

    Threat.reselect(entity, opts)
  end

  describe "add/3" do
    test "creates and accumulates entries" do
      entity = mob() |> Threat.add(@player_a, 50) |> Threat.add(@player_a, 25)
      assert entity.internal.threat == %{@player_a => 75.0}
    end

    test "ignores self, invalid guids, and negative amounts" do
      entity =
        mob()
        |> Threat.add(@mob_guid, 50)
        |> Threat.add(nil, 50)
        |> Threat.add(0, 50)
        |> Threat.add(@player_a, -10)

      assert entity.internal.threat == %{}
    end

    test "seeds a zero-threat entry" do
      entity = Threat.add(mob(), @player_a, 0)
      assert entity.internal.threat == %{@player_a => 0.0}
    end
  end

  describe "add_damage/3" do
    test "accrues threat while in combat" do
      entity = Threat.add_damage(mob(), @player_a, 40)
      assert entity.internal.threat == %{@player_a => 40.0}
    end

    test "ignores damage while out of combat" do
      entity = Threat.add_damage(mob(in_combat: false), @player_a, 40)
      assert entity.internal.threat == %{}
    end
  end

  describe "taunt/2" do
    test "raises the taunter to the top threat" do
      entity =
        mob(threat: %{@player_a => 200.0, @player_b => 50.0})
        |> Threat.taunt(@player_b)

      assert entity.internal.threat == %{@player_a => 200.0, @player_b => 200.0}
    end

    test "keeps a higher taunter threat unchanged" do
      entity =
        mob(threat: %{@player_a => 300.0, @player_b => 50.0})
        |> Threat.taunt(@player_a)

      assert entity.internal.threat == %{@player_a => 300.0, @player_b => 50.0}
    end
  end

  describe "modify/3" do
    test "feint-style reductions cannot make threat negative" do
      entity = mob(threat: %{@player_a => 100.0}) |> Threat.modify(@player_a, -150)
      assert entity.internal.threat == %{@player_a => 0.0}
    end
  end

  describe "change/3" do
    test "positive spell threat creates an entry" do
      entity = Threat.change(mob(), @player_a, 10)
      assert entity.internal.threat == %{@player_a => 10.0}
    end

    test "negative spell threat only reduces an existing entry" do
      empty = Threat.change(mob(), @player_a, -10)
      reduced = mob(threat: %{@player_a => 30.0}) |> Threat.change(@player_a, -10)

      assert empty.internal.threat == %{}
      assert reduced.internal.threat == %{@player_a => 20.0}
    end
  end

  describe "wipe/1 and tracking?/2 and entries/1" do
    test "wipe empties the table" do
      entity = mob(threat: %{@player_a => 10.0}) |> Threat.wipe()
      assert entity.internal.threat == %{}
    end

    test "tracking? reflects table membership" do
      entity = mob(threat: %{@player_a => 10.0})
      assert Threat.tracking?(entity, @player_a)
      refute Threat.tracking?(entity, @player_b)
    end

    test "entries are sorted by threat descending" do
      entity = mob(threat: %{@player_a => 10.0, @player_b => 30.0, @player_c => 20.0})
      assert Threat.entries(entity) == [{@player_b, 30.0}, {@player_c, 20.0}, {@player_a, 10.0}]
    end
  end

  describe "threat ref events" do
    test "add enqueues threat_ref_gained only for new entries" do
      entity = mob() |> Threat.add(@player_a, 10) |> Threat.add(@player_a, 10)

      assert [%Event{type: :threat_ref_gained, target_guid: @player_a}] = entity.internal.events
    end

    test "wipe enqueues threat_ref_lost for each entry" do
      entity = Threat.wipe(mob(threat: %{@player_a => 1.0, @player_b => 2.0}))

      lost =
        entity.internal.events
        |> Enum.filter(&(&1.type == :threat_ref_lost))
        |> Enum.map(& &1.target_guid)
        |> Enum.sort()

      assert lost == [@player_a, @player_b]
      assert entity.internal.threat == %{}
    end

    test "reselect enqueues threat_ref_lost for pruned entries" do
      entity = mob(target: @player_a, threat: %{@player_a => 100.0, @player_b => 10.0})
      {entity, _decision} = reselect(entity, valid?: fn guid -> guid != @player_a end)

      assert [%Event{type: :threat_ref_lost, target_guid: @player_a}] = entity.internal.events
    end

    test "taunt seeds a missing taunter at top threat with a gained event" do
      entity = Threat.taunt(mob(threat: %{@player_a => 200.0}), @player_b)

      assert entity.internal.threat == %{@player_a => 200.0, @player_b => 200.0}
      assert [%Event{type: :threat_ref_gained, target_guid: @player_b}] = entity.internal.events
    end
  end

  describe "reselect/2" do
    test "keeps an empty decision on an empty table" do
      assert {_entity, :keep} = reselect(mob())
    end

    test "picks the highest threat when there is no current victim" do
      entity = mob(threat: %{@player_a => 10.0, @player_b => 30.0})
      assert {_entity, {:switch, @player_b}} = reselect(entity)
    end

    test "selects a player who attacked a neutral mob" do
      mob_guid = Guid.from_low_guid(:mob, 7, unique_guid())
      player_guid = Guid.from_low_guid(:player, unique_guid())

      Metadata.put(mob_guid, %{faction_template: neutral_creature()})

      Metadata.put(player_guid, %{
        alive?: true,
        faction_template: alliance(),
        unit_flags: 0
      })

      on_exit(fn ->
        Metadata.delete(mob_guid)
        Metadata.delete(player_guid)
      end)

      entity = mob(guid: mob_guid, threat: %{player_guid => 10.0})

      assert {_entity, {:switch, ^player_guid}} =
               Threat.reselect(entity, in_melee?: fn _guid -> false end)
    end

    test "switches away from an invalid victim" do
      entity = mob(target: @player_a, threat: %{@player_a => 100.0, @player_b => 10.0})
      {entity, decision} = reselect(entity, valid?: fn guid -> guid != @player_a end)

      assert decision == {:switch, @player_b}
      assert entity.internal.threat == %{@player_b => 10.0}
    end

    test "keeps the current victim below the 110% threshold" do
      entity = mob(target: @player_a, threat: %{@player_a => 100.0, @player_b => 109.0})
      assert {_entity, :keep} = reselect(entity, in_melee?: fn _guid -> true end)
    end

    test "switches above 110% in melee range" do
      entity = mob(target: @player_a, threat: %{@player_a => 100.0, @player_b => 115.0})
      assert {_entity, {:switch, @player_b}} = reselect(entity, in_melee?: fn _guid -> true end)
    end

    test "keeps the current victim between 110% and 130% at range" do
      entity = mob(target: @player_a, threat: %{@player_a => 100.0, @player_b => 115.0})
      assert {_entity, :keep} = reselect(entity)
    end

    test "switches above 130% regardless of range" do
      entity = mob(target: @player_a, threat: %{@player_a => 100.0, @player_b => 131.0})
      assert {_entity, {:switch, @player_b}} = reselect(entity)
    end

    test "skips a ranged mid-threshold candidate but takes a melee one further down" do
      entity =
        mob(
          target: @player_a,
          threat: %{@player_a => 100.0, @player_b => 125.0, @player_c => 115.0}
        )

      assert {_entity, {:switch, @player_c}} = reselect(entity, in_melee?: fn guid -> guid == @player_c end)
    end

    test "keeps the current victim when it tops the table" do
      entity = mob(target: @player_a, threat: %{@player_a => 100.0, @player_b => 50.0})
      assert {_entity, :keep} = reselect(entity, in_melee?: fn _guid -> true end)
    end

    test "no-ops for entities without a threat table" do
      entity = %Mob{object: %Object{guid: @mob_guid}, unit: %Unit{}, internal: %Internal{}}
      assert {^entity, :keep} = Threat.reselect(entity, valid?: fn _ -> true end, in_melee?: fn _ -> false end)
    end
  end

  defp alliance do
    %FactionTemplate{id: 1, faction: 1, flags: 72, faction_group: 3, friend_group: 2, enemy_group: 12}
  end

  defp neutral_creature do
    %FactionTemplate{id: 7, faction: 7, flags: 0, faction_group: 0, friend_group: 0, enemy_group: 0}
  end

  defp unique_guid do
    System.unique_integer([:positive, :monotonic])
  end
end
