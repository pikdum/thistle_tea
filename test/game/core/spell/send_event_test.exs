defmodule ThistleTea.Game.Core.Spell.SendEventTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.CastContext
  alias ThistleTea.Game.Core.Spell.Casting
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.Core.Spell.SendEvent
  alias ThistleTea.Game.Core.Spell.SpellEffect
  alias ThistleTea.Game.Core.Spell.Target
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Test.Unique

  @steps [%ScriptStep{command: :summon_creature, datalong: 5_676}]

  setup [:caster]

  describe "Casting.start/4" do
    test "runs a target-less event once from the caster, aimed at nothing", %{caster: caster} do
      caster = caster |> Casting.start(spell(nil), Target.none(), 1_000) |> Casting.complete(1_000)

      assert [%Effects.ScriptSteps{steps: steps, target_guid: 0}] = script_events(caster)
      assert steps == @steps
    end

    test "leaves an event without script steps silent", %{caster: caster} do
      spell = %{spell(nil) | effects: [%{hd(spell(nil).effects) | event_steps: []}]}
      caster = caster |> Casting.start(spell, Target.none(), 1_000) |> Casting.complete(1_000)

      assert script_events(caster) == []
    end
  end

  describe "SpellEffect.receive/4" do
    test "a caster-targeted event runs on the caster", %{caster: caster, context: context} do
      guid = caster.object.guid
      assert {_, [event]} = SpellEffect.receive(caster, context, spell(:caster), 1_000)
      assert event == Effects.script_steps(@steps, guid, 0)
    end

    test "a scripted unit target asks the caster to run the event at it", %{caster: caster, context: context} do
      target = %{caster | object: %Object{guid: Unique.integer()}}
      context = %{context | target_role: :other}

      assert {_, [event]} = SpellEffect.receive(target, context, spell(:creature_near_caster), 1_000)
      assert event == Effects.forward_script_steps(caster.object.guid, @steps, target.object.guid)
    end

    test "a target-less event never runs per recipient", %{caster: caster, context: context} do
      assert {_, []} = SpellEffect.receive(caster, context, spell(nil), 1_000)
    end
  end

  describe "SendEvent.cast_events/4" do
    test "a resolver that is not the caster forwards the event to it" do
      assert SendEvent.cast_events(spell(nil), 2, 1, 3) == [Effects.forward_script_steps(1, @steps, 3)]
    end

    test "targeted events are left to their recipients" do
      assert SendEvent.cast_events(spell(:caster), 1, 1, 1) == []
      refute SendEvent.cast_level?(spell(:caster))
    end
  end

  describe "SendEvent.target/4" do
    test "prefers the focus, then the object, then the selected unit" do
      assert SendEvent.target(10, [20], 30, 1) == 10
      assert SendEvent.target(nil, [20], 30, 1) == 20
      assert SendEvent.target(nil, [nil], 30, 1) == 30
    end

    test "has no target when only the caster could be one" do
      assert SendEvent.target(nil, [], nil, 1) == 0
      assert SendEvent.target(nil, [], 1, 1) == 0
    end
  end

  defp script_events(entity) do
    Enum.filter(entity.internal.events || [], &is_struct(&1, Effects.ScriptSteps))
  end

  defp spell(implicit_target) do
    %Spell{
      id: 7_728,
      cast_time_ms: 0,
      effects: [
        %Effect{
          index: 0,
          type: :send_event,
          misc_value: 1_131,
          implicit_target_a: implicit_target,
          event_steps: @steps
        }
      ]
    }
  end

  defp caster(_context) do
    world = WorldRef.open(0)
    guid = Unique.integer()

    caster = %Mob{
      object: %Object{guid: guid},
      unit: %Unit{health: 100, max_health: 100, level: 10},
      internal: %Internal{world: world}
    }

    %{caster: caster, context: %CastContext{caster_guid: guid, caster_level: 10}}
  end
end
