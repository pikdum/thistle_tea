defmodule ThistleTea.Game.Core.Creature.GuardCallTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.BT.Context.Perception
  alias ThistleTea.Game.Core.AI.BT.Context.Perception.Observation
  alias ThistleTea.Game.Core.Combat.Engagement
  alias ThistleTea.Game.Core.Combat.FactionTemplate
  alias ThistleTea.Game.Core.Creature.GuardCall
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Creature
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Pet.SummonEvent
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Test.Unique

  @calls_guards 0x08000000
  @no_aggro 0x2

  describe "watch_range/1" do
    test "watches the detection range of a civilian that cannot attack on sight" do
      assert GuardCall.watch_range(civilian()) == 18.0
    end

    test "leaves attack-on-sight callers to aggro until they fight" do
      fighter = civilian(extra_flags: 0)
      assert GuardCall.watch_range(fighter) == nil
      assert GuardCall.watch_range(%{fighter | internal: %{fighter.internal | in_combat: true}}) == 18.0
    end

    test "ignores creatures without the flag, dead civilians, and answered calls" do
      assert GuardCall.watch_range(civilian(static_flags: 0)) == nil
      assert GuardCall.watch_range(%{civilian() | unit: %{civilian().unit | health: 0}}) == nil
      assert GuardCall.watch_range(civilian(guard_call: {:summoned, 68})) == nil
      assert GuardCall.watch_range(civilian(guard_call: :held)) == nil
    end

    test "keeps watching while a call is pending so a denial changes nothing" do
      pending = civilian(guard_call: :pending)

      assert GuardCall.watch_range(pending) == 18.0
      refute GuardCall.ready?(pending)
      assert GuardCall.watch_range(GuardCall.answered(pending, :denied)) == GuardCall.watch_range(pending)
    end
  end

  describe "request/2" do
    test "makes one call until it is answered" do
      enemy = player_guid()
      mob = GuardCall.request(civilian(), enemy)

      assert mob.internal.creature.guard_call == :pending
      assert [%Effects.CallGuards{enemy_guid: ^enemy}] = mob.internal.events
      assert GuardCall.request(mob, enemy).internal.events == mob.internal.events
    end

    test "is made when a caller enters combat" do
      enemy = player_guid()
      %Engagement.Result{entity: mob} = Engagement.enter(civilian(), enemy, 1_000, selection: :target)

      assert mob.internal.creature.guard_call == :pending
      assert Enum.any?(mob.internal.events, &match?(%Effects.CallGuards{enemy_guid: ^enemy}, &1))
    end
  end

  describe "answered/2" do
    test "a denied call leaves the civilian watching" do
      mob = civilian(guard_call: :pending) |> GuardCall.answered(:denied)
      assert GuardCall.ready?(mob)
    end

    test "a summoned guard holds the civilian until it dies or leaves" do
      mob = civilian(guard_call: :pending) |> GuardCall.answered({:summoned, 68})
      refute GuardCall.ready?(mob)

      assert GuardCall.summon_ended(mob, summon_event(:summoned_just_died, 1642)) == mob
      assert GuardCall.ready?(GuardCall.summon_ended(mob, summon_event(:summoned_just_died, 68)))
      assert GuardCall.ready?(GuardCall.summon_ended(mob, summon_event(:summoned_just_despawn, 68)))
    end

    test "any other answer holds until respawn" do
      mob = civilian(guard_call: :pending) |> GuardCall.answered(:held)

      refute GuardCall.ready?(GuardCall.summon_ended(mob, summon_event(:summoned_just_died, 68)))
      assert GuardCall.ready?(GuardCall.reset(mob))
    end
  end

  describe "sees?/3" do
    test "sees an enemy player within range and line of sight" do
      mob = civilian()
      enemy = player_guid()

      assert GuardCall.sees?(mob, enemy, context(mob, enemy, distance: 15.0))
      refute GuardCall.sees?(mob, enemy, context(mob, enemy, distance: 19.0))
      refute GuardCall.sees?(mob, enemy, context(mob, enemy, distance: 15.0, line_of_sight?: false))
      refute GuardCall.sees?(mob, enemy, context(mob, enemy, distance: 15.0, z: 8.0))
    end

    test "ignores friendly players and enemy creatures" do
      mob = civilian()
      friend = player_guid()
      creature = Guid.from_low_guid(:mob, 1, Unique.integer())

      refute GuardCall.sees?(mob, friend, context(mob, friend, distance: 5.0, faction_template: stormwind()))
      refute GuardCall.sees?(mob, creature, context(mob, creature, distance: 5.0))
    end

    test "watches only its victim while fighting" do
      victim = player_guid()
      bystander = player_guid()
      mob = civilian()
      mob = %{mob | unit: %{mob.unit | target: victim}, internal: %{mob.internal | in_combat: true}}

      assert GuardCall.sees?(mob, victim, context(mob, victim, distance: 5.0))
      refute GuardCall.sees?(mob, bystander, context(mob, bystander, distance: 5.0))
    end
  end

  defp civilian(opts \\ []) do
    %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, 1, Unique.integer()), entry: 1},
      unit: %Unit{level: 10, health: 100, max_health: 100, faction_template: 12, flags: 0},
      internal: %Internal{
        world: WorldRef.open(0),
        in_combat: false,
        creature: %Creature{
          detection_range: 18.0,
          static_flags: Keyword.get(opts, :static_flags, @calls_guards),
          extra_flags: Keyword.get(opts, :extra_flags, @no_aggro),
          guard_call: Keyword.get(opts, :guard_call)
        }
      },
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }
  end

  defp context(mob, enemy, opts) do
    distance = Keyword.fetch!(opts, :distance)
    world = WorldRef.open(0)

    own = %Observation{
      guid: mob.object.guid,
      position: {world, 0.0, 0.0, 0.0},
      distance: 0.0,
      metadata: %{alive?: true, level: 10, unit_flags: 0, faction_template: stormwind()}
    }

    target = %Observation{
      guid: enemy,
      position: {world, distance, 0.0, Keyword.get(opts, :z, 0.0)},
      distance: distance,
      line_of_sight?: Keyword.get(opts, :line_of_sight?, true),
      metadata: %{
        alive?: true,
        level: 10,
        unit_flags: 0,
        faction_template: Keyword.get(opts, :faction_template, orgrimmar())
      }
    }

    perception = Perception.new(1_000, nil, %{mob.object.guid => own, enemy => target}, %{})
    Context.new(1_000, perception: perception)
  end

  defp summon_event(event, entry),
    do: %SummonEvent{event: event, entry: entry, world: WorldRef.open(0), observation: nil}

  defp player_guid, do: Guid.from_low_guid(:player, Unique.integer())

  defp stormwind do
    %FactionTemplate{id: 12, faction: 72, flags: 0, faction_group: 2, friend_group: 2, enemy_group: 4}
  end

  defp orgrimmar do
    %FactionTemplate{id: 2, faction: 2, flags: 72, faction_group: 5, friend_group: 4, enemy_group: 10}
  end
end
