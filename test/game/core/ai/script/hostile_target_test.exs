defmodule ThistleTea.Game.Core.AI.Script.HostileTargetTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.BT.Context.Perception
  alias ThistleTea.Game.Core.AI.BT.Context.Perception.Observation
  alias ThistleTea.Game.Core.AI.BT.Context.Random
  alias ThistleTea.Game.Core.AI.Script
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Math
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Test.Unique

  setup [:caster]

  describe "execute_steps/5" do
    test "filters spell range, line of sight and player flags before choosing", %{mob: mob, step: step} do
      player = Unique.integer()
      npc = Guid.from_low_guid(:mob, Unique.integer(), Unique.integer())

      observations = [
        observation(mob, Unique.integer(), {50.0, 0.0, 0.0}),
        observation(mob, Unique.integer(), {38.0, 0.0, 0.0}, line_of_sight?: false),
        observation(mob, Unique.integer(), {35.0, 0.0, 0.0}, alive?: false),
        observation(mob, npc, {30.0, 0.0, 0.0}),
        observation(mob, player, {20.0, 0.0, 0.0})
      ]

      assert targets(cast(mob, step, observations)) == [player]
    end

    test "filters minimum spell range and other copies before random selection", %{mob: mob, step: step} do
      player = Unique.integer()
      spell = %{mob.internal.spellbook[step.datalong] | min_range_yards: 10.0}
      mob = %{mob | internal: %{mob.internal | spellbook: %{spell.id => spell}}}
      step = %{step | target_type: :hostile_random}
      other = observation(mob, Unique.integer(), {30.0, 0.0, 0.0})
      other = %{other | position: {WorldRef.instance(409, Unique.integer()), 30.0, 0.0, 0.0}}

      observations = [
        observation(mob, Unique.integer(), {5.0, 0.0, 0.0}),
        other,
        observation(mob, player, {15.0, 0.0, 0.0})
      ]

      assert targets(cast(mob, step, observations)) == [player]
    end

    test "selector range includes the minimum and excludes the maximum", %{mob: mob, step: step} do
      player = Unique.integer()
      spell = %{mob.internal.spellbook[step.datalong] | min_range_yards: 10.0}
      mob = %{mob | internal: %{mob.internal | spellbook: %{spell.id => spell}}}

      for {distance, expected} <- [{12.99, []}, {13.0, [player]}, {42.99, [player]}, {43.0, []}] do
        assert targets(cast(mob, step, [observation(mob, player, {distance, 0.0, 0.0})])) == expected
      end
    end

    test "farthest ranking uses combat reach rather than center distance", %{mob: mob, step: step} do
      player = Unique.integer()

      observations = [
        observation(mob, Unique.integer(), {20.0, 0.0, 0.0}, combat_reach: 12.0),
        observation(mob, player, {18.0, 0.0, 0.0})
      ]

      assert targets(cast(mob, step, observations)) == [player]
    end

    test "excludes the original top threat before range filtering", %{mob: mob, step: step} do
      top = Unique.integer()
      second = Unique.integer()
      third = Unique.integer()

      observations = [
        observation(mob, top, {80.0, 0.0, 0.0}),
        observation(mob, second, {20.0, 0.0, 0.0}),
        observation(mob, third, {30.0, 0.0, 0.0})
      ]

      threat = %{top => 100, second => 50, third => 10}

      for selector <- [:hostile_second_aggro, :hostile_random_not_top] do
        assert targets(cast(mob, %{step | target_type: selector}, observations, threat)) == [second]
      end
    end

    test "checks horizontal surface distance after choosing the farthest", %{mob: mob, step: step} do
      player = Unique.integer()
      nearer = observation(mob, Unique.integer(), {14.0, 0.0, 0.0})
      step = %{step | minimum_target_distance_2d: 7.0}

      for x <- [6.0, 9.0] do
        above = observation(mob, player, {x, 0.0, 30.0})
        assert targets(cast(mob, step, [nearer, above])) == []
      end

      above = observation(mob, player, {9.01, 0.0, 30.0})
      assert targets(cast(mob, step, [nearer, above])) == [player]
    end
  end

  defp caster(_context) do
    spell = %Spell{id: Unique.integer(), range_yards: 40.0, effects: []}

    mob = %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, Unique.integer(), Unique.integer())},
      unit: %Unit{health: 100, max_health: 100, combat_reach: 1.5, bounding_radius: 1.0},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{world: WorldRef.instance(409, Unique.integer()), spellbook: %{spell.id => spell}}
    }

    step = %ScriptStep{
      command: :cast_spell,
      datalong: spell.id,
      datalong2: 0x02,
      target_type: :hostile_farthest,
      target_param1: 0x03,
      abort_on_failure?: true
    }

    %{mob: mob, step: step}
  end

  defp observation(mob, guid, {x, y, z} = position, opts \\ []) do
    %Observation{
      guid: guid,
      position: {mob.internal.world, x, y, z},
      distance: Math.distance({0.0, 0.0, 0.0}, position),
      line_of_sight?: Keyword.get(opts, :line_of_sight?, true),
      metadata: %{
        alive?: Keyword.get(opts, :alive?, true),
        combat_reach: Keyword.get(opts, :combat_reach, 1.5),
        bounding_radius: 1.0
      }
    }
  end

  defp cast(mob, step, observations, threat \\ nil) do
    threat = threat || Map.new(observations, &{&1.guid, 1})
    mob = %{mob | internal: %{mob.internal | threat: threat}}
    perception = Perception.new(0, {mob.internal.world, 0.0, 0.0, 0.0}, Map.new(observations, &{&1.guid, &1}), %{})

    context = Context.new(0, perception: perception, random: Random.fixed())
    {mob, _blackboard} = Script.execute_steps(mob, Blackboard.new(), [step], nil, context)

    mob
  end

  defp targets(mob), do: for(%Effects.TriggerSpell{target_guid: guid} <- mob.internal.events, do: guid)
end
