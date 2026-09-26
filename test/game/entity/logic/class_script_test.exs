defmodule ThistleTea.Game.Entity.Logic.ClassScriptTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura, as: AuraData
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Aura.ClassScript
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellFeedback
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.ProcRule

  describe "events/4" do
    test "Nightfall preserves the proc source and cast item for ordinary spell targeting" do
      holder = %{holder(4309) | cast_item_guid: 99}

      assert [
               %Effects.TriggerSpell{
                 source_guid: 1,
                 source_level: 60,
                 target_guid: 2,
                 spell_id: 17_941,
                 cast_item_guid: 99,
                 triggering_spell_id: 18_094
               }
             ] = ClassScript.events(holder, 1, context())
    end

    test "all supported scripts reject dead or missing targets" do
      for script <- [4309, 836, 988, 989, 4086, 4087, 3656, 4533, 4537] do
        for invalid <- [
              %{context() | victim_alive?: false},
              Map.delete(context(), :victim_alive?),
              Map.delete(context(), :victim_guid)
            ] do
          assert ClassScript.events(holder(script), 1, invalid) == []
        end
      end
    end

    test "Improved Blizzard chooses each chill rank only for Blizzard's visual" do
      context = %{context() | spell: %Spell{id: 10, spell_visual: 259}}

      for {script, chill} <- [{836, 12_484}, {988, 12_485}, {989, 12_486}] do
        assert [%Effects.TriggerSpell{spell_id: ^chill}] = ClassScript.events(holder(script), 1, context)
        assert ClassScript.events(holder(script), 1, %{context | spell: %Spell{id: 116}}) == []
      end
    end

    test "Improved Mend Pet rolls the aura amount independently for both ranks" do
      for {script, chance} <- [{4086, 15}, {4087, 50}] do
        holder = %{
          holder(script)
          | auras: [%AuraData{type: :override_class_scripts, misc_value: script, amount: chance}]
        }

        assert [%Effects.TriggerSpell{spell_id: 24_406}] =
                 ClassScript.events(holder, 1, context(), fn -> chance / 100 end)

        assert ClassScript.events(holder, 1, context(), fn -> (chance + 1) / 100 end) == []
      end
    end

    test "Corrupted Healing requires a direct heal effect" do
      direct = %{context() | spell: %Spell{id: 2050, effects: [%Effect{type: :heal}]}}
      periodic = %{context() | spell: %Spell{id: 139, effects: [%Effect{type: :apply_aura, aura: :periodic_heal}]}}
      assert [%Effects.TriggerSpell{spell_id: 23_402}] = ClassScript.events(holder(3656), 1, direct)
      assert ClassScript.events(holder(3656), 1, periodic) == []
    end

    test "Rejuvenation follows the recipient's current resource, including shapeshifts" do
      context = %{context() | spell: %Spell{id: 774, spell_family: 7, family_flags_0: 0x10}}

      for {power, trigger} <- [{0, 28_722}, {1, 28_723}, {3, 28_724}] do
        assert [%Effects.TriggerSpell{spell_id: ^trigger, target_guid: 2}] =
                 ClassScript.events(holder(4533), 1, %{context | victim_power_type: power})
      end

      for power <- [2, 4, nil] do
        assert ClassScript.events(holder(4533), 1, %{context | victim_power_type: power}) == []
      end

      for spell <- [
            %Spell{id: 139, spell_family: 6, family_flags_0: 0x10},
            %Spell{id: 8936, spell_family: 7, family_flags_0: 0x40}
          ] do
        assert ClassScript.events(holder(4533), 1, %{context | spell: spell}) == []
      end
    end

    test "Regrowth triggers the health bonus only for its druid family" do
      context = %{context() | spell: %Spell{id: 8936, spell_family: 7, family_flags_0: 0x40}}
      assert [%Effects.TriggerSpell{spell_id: 28_750}] = ClassScript.events(holder(4537), 1, context)

      assert ClassScript.events(holder(4537), 1, %{
               context
               | spell: %Spell{id: 774, spell_family: 7, family_flags_0: 0x10}
             }) == []

      assert ClassScript.events(holder(9999), 1, context) == []
    end
  end

  describe "reactions/3" do
    test "successful triggers share charge consumption and cooldowns" do
      holder = %{holder(4309) | charges: 2}
      holder = %{holder | spell: %{holder.spell | proc_rule: %{holder.spell.proc_rule | cooldown_ms: 1_000}}}
      entity = entity(holder)
      {spent, [%Effects.TriggerSpell{}]} = Aura.reactions(entity, :spell_hit_dealt, context())
      assert [%Holder{charges: 1, next_proc_at: 2_000}] = spent.unit.auras
      assert {^spent, []} = Aura.reactions(spent, :spell_hit_dealt, %{context() | now: 1_999})
      {exhausted, events} = Aura.reactions(spent, :spell_hit_dealt, %{context() | now: 2_000})
      assert Enum.any?(events, &match?(%Effects.TriggerSpell{}, &1))
      assert exhausted.unit.auras == []
    end

    test "failed script conditions preserve charges and do not start a cooldown" do
      for script <- [4309, 989, 3656, 4533, 4537, 9999] do
        entity = entity(%{holder(script) | charges: 2})
        assert {^entity, []} = Aura.reactions(entity, :spell_hit_dealt, %{context() | victim_alive?: false})
      end
    end

    test "shared eligibility rejects unrelated families, direct damage, cast completion and self procs" do
      entity = entity(holder(4309))

      assert {^entity, []} =
               Aura.reactions(entity, :spell_hit_dealt, %{context() | spell: %Spell{id: 133, spell_family: 3}})

      assert {^entity, []} = Aura.reactions(entity, :spell_hit_dealt, %{context() | proc_type: :deal_harmful_spell})
      assert {^entity, []} = Aura.reactions(entity, :spell_cast_completed, %{context() | outcome: :cast_end})
      assert {^entity, []} = Aura.reactions(entity, :spell_hit_dealt, %{context() | spell: holder(4309).spell})
    end

    test "resolved caster feedback queues the trigger without mutating a foreign target" do
      caster = entity(holder(4309))
      context = context()
      updated = SpellFeedback.receive(caster, Map.delete(context, :spell), context.spell, 1_000)
      assert [%Effects.TriggerSpell{spell_id: 17_941}] = updated.internal.events
      assert updated.unit == caster.unit
    end
  end

  defp holder(script) do
    %Holder{
      spell: %Spell{
        id: 18_094,
        proc_chance: 100,
        proc_rule: %ProcRule{proc_flags: 0x40000, spell_family: 5, family_mask_0: 0xA}
      },
      caster_guid: 1,
      caster_level: 60,
      auras: [%AuraData{type: :override_class_scripts, misc_value: script, amount: 100}]
    }
  end

  defp context do
    %{
      spell: %Spell{id: 172, spell_family: 5, family_flags_0: 0x2},
      victim_guid: 2,
      victim_alive?: true,
      victim_power_type: 0,
      proc_type: :deal_harmful_periodic,
      outcome: :normal,
      now: 1_000
    }
  end

  defp entity(holder) do
    %Mob{
      object: %Object{guid: 1},
      unit: %Unit{level: 60, health: 100, max_health: 100, auras: [holder]},
      internal: %Internal{}
    }
  end
end
