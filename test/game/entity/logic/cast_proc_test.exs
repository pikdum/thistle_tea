defmodule ThistleTea.Game.Entity.Logic.CastProcTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellFeedback
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.CastResolution
  alias ThistleTea.Game.Spell.CastResolution.Costs
  alias ThistleTea.Game.Spell.CastResolution.Followups
  alias ThistleTea.Game.Spell.CastResolution.Impact
  alias ThistleTea.Game.Spell.CastResolution.PowerCost
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.ProcRule
  alias ThistleTea.Game.Spell.Target

  setup [:caster]

  describe "complete/3" do
    test "area casts trigger once and later impacts cannot spend another charge", %{caster: caster} do
      cast = launch_cast()
      result = Casting.complete(caster, cast, 1_000)
      assert Enum.count(result.internal.events, &is_struct(&1, Effects.DeliverSpell)) == 2
      assert triggers(result) == [9_001]
      assert hd(result.unit.auras).charges == 2

      for target <- [2, 3] do
        payload = %{victim_guid: target, proc_type: :deal_harmful_spell, outcome: :normal, damage: 20}
        updated = SpellFeedback.receive(clear_events(result), payload, cast.spell, 1_100)
        assert triggers(updated) == []
        assert hd(updated.unit.auras).charges == 2
      end
    end

    test "a fully resisted cast can trigger at launch", %{caster: caster} do
      cast = launch_cast()
      resolution = %{cast.resolution | hits: [], impacts: [], misses: [%{guid: 2, reason: 2}]}
      result = Casting.complete(caster, %{cast | resolution: resolution}, 1_000)
      assert triggers(result) == [9_001]
    end

    test "preparation and cancellation leave cast-completion charges alone", %{caster: caster} do
      cast = %{launch_cast() | phase: :preparing, started_at: 1_000, cast_time_ms: 3_000, ends_at: 4_000}
      caster = %{caster | internal: %{caster.internal | casting: cast}}
      assert {:waiting, waiting, 2_000} = Casting.advance(caster, 2_000)
      assert triggers(waiting) == []
      cancelled = Casting.cancel(waiting, 2_000)
      assert triggers(cancelled) == []
      assert hd(cancelled.unit.auras).charges == 3
      assert {:idle, ^cancelled} = Casting.advance(cancelled, 4_000)
    end

    test "channels trigger on launch and do not repeat at ticks or finish", %{caster: caster} do
      cast = launch_cast()
      spell = %{cast.spell | attributes: MapSet.new([:channeled])}

      cast = %{
        cast
        | spell: spell,
          channel_ms: 3_000,
          channel_tick_ms: 1_000,
          next_channel_tick_at: 2_000,
          ends_at: 4_000
      }

      result = Casting.complete(caster, cast, 1_000)
      assert triggers(result) == [9_001]
      assert result.internal.casting.phase == :channel_tick
      assert {:waiting, result, _} = Casting.advance(clear_events(result), 2_000)
      assert triggers(result) == []
      assert {:finished, result} = Casting.advance(clear_events(result), 4_000)
      assert triggers(result) == []
      assert hd(result.unit.auras).charges == 2
    end

    test "positive item casts and caster-suppressed spells cannot trigger", %{caster: caster} do
      cast = launch_cast()
      positive = %{cast.spell | effects: [], dmg_class: 1}

      for cast <- [
            %{cast | spell: positive, cast_item_guid: 10},
            %{cast | spell: %{cast.spell | attributes: MapSet.new([:suppress_caster_procs])}}
          ] do
        result = Casting.complete(caster, cast, 1_000)
        assert triggers(result) == []
        assert hd(result.unit.auras).charges == 3
      end
    end

    test "helpful casts with no unit target use the caster for their proc", %{caster: caster} do
      cast = launch_cast()

      resolution = %{
        cast.resolution
        | hits: [],
          impacts: [],
          followups: %{cast.resolution.followups | selected_unit_guid: nil}
      }

      cast = %{cast | spell: %{cast.spell | effects: []}, resolution: resolution}
      result = Casting.complete(caster, cast, 1_000)

      assert [%Effects.TriggerSpell{target_guid: 1}] =
               Enum.filter(result.internal.events, &is_struct(&1, Effects.TriggerSpell))
    end
  end

  defp caster(_context) do
    holder = %Holder{
      spell: %Spell{id: 9_000, proc_type_mask: 0x14400, proc_chance: 100, proc_rule: %ProcRule{proc_ex: 0x80000}},
      caster_guid: 1,
      charges: 3,
      auras: [%Aura{type: :proc_trigger_spell, trigger_spell_id: 9_001}]
    }

    %{
      caster: %Mob{
        object: %Object{guid: 1},
        unit: %Unit{
          health: 100,
          max_health: 100,
          level: 20,
          power_type: 0,
          power1: 100,
          max_power1: 100,
          auras: [holder]
        },
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{}
      }
    }
  end

  defp launch_cast do
    spell = %Spell{id: 116, school: :frost, effects: [%Effect{type: :school_damage, base_points: 10}]}

    resolution = %CastResolution{
      hits: [2, 3],
      misses: [],
      costs: %Costs{
        power: %PowerCost{power_type: nil, amount: 0},
        channel_power: %PowerCost{power_type: nil, amount: 0},
        reagents: [],
        cast_item_guid: nil,
        modifier_holder_ids: []
      },
      impacts: [%Impact{target_guid: 2, target_role: :other}, %Impact{target_guid: 3, target_role: :other}],
      followups: %Followups{
        packet_hits: [2, 3],
        selected_unit_guid: 2,
        object_guid: nil,
        item_guid: nil,
        ground_position: nil,
        area_position: nil
      }
    }

    %{Cast.new(spell, Target.none(), 1_000) | phase: :launch, resolution: resolution}
  end

  defp triggers(entity), do: for(%Effects.TriggerSpell{spell_id: id} <- entity.internal.events, do: id)
  defp clear_events(entity), do: %{entity | internal: %{entity.internal | events: []}}
end
