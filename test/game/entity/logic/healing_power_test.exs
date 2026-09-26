defmodule ThistleTea.Game.Entity.Logic.HealingPowerTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura, as: AuraData
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Aura.HealingPower
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellFeedback
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.ProcRule

  setup [:healer]

  describe "events/3" do
    test "selects all recipient classes independently of their active resource" do
      for {id, buffs} <- [
            {28_789, [28_790, 28_795, 28_791, 28_791, 28_795, 28_795, 28_793, 28_793, 28_795]},
            {28_823, [28_827, 28_824, 28_826, 28_826, 28_824, 28_824, 28_825, 28_825, 28_824]}
          ],
          {class, buff} <- Enum.zip([1, 2, 3, 4, 5, 7, 8, 9, 11], buffs),
          power <- [0, 1, 3] do
        context = %{context() | victim_class: class, victim_power_type: power}

        assert [
                 %Effects.TriggerSpell{
                   source_guid: 1,
                   source_level: 60,
                   target_guid: 2,
                   spell_id: ^buff,
                   triggering_spell_id: ^id,
                   cast_item_guid: 99,
                   requires_living_target?: true
                 }
               ] = HealingPower.events(holder(id), 1, context)
      end
    end

    test "ignores unknown classes and dead or missing recipients" do
      for id <- [28_789, 28_823],
          invalid <- [
            %{context() | victim_class: 0},
            %{context() | victim_class: 6},
            %{context() | victim_class: nil},
            %{context() | victim_alive?: false},
            Map.delete(context(), :victim_class),
            Map.delete(context(), :victim_guid),
            Map.delete(context(), :victim_alive?)
          ] do
        assert HealingPower.events(holder(id), 1, invalid) == []
      end

      assert HealingPower.events(holder(1), 1, context()) == []
    end
  end

  describe "reactions/3" do
    test "successful procs use shared charges and cooldowns", %{healer: healer} do
      {spent, [%Effects.TriggerSpell{spell_id: 28_793}]} = Aura.reactions(healer, :spell_hit_dealt, context())
      assert [%Holder{charges: 1, next_proc_at: 2_000}] = spent.unit.auras
      assert {^spent, []} = Aura.reactions(spent, :spell_hit_dealt, %{context() | now: 1_999})
      {exhausted, events} = Aura.reactions(spent, :spell_hit_dealt, %{context() | now: 2_000})
      assert Enum.count(events, &is_struct(&1, Effects.TriggerSpell)) == 1
      assert exhausted.unit.auras == []
    end

    test "eligibility rejects other heals, damage, periodic healing and cast completion", %{healer: healer} do
      for invalid <- [
            %{context() | spell: %Spell{id: 2050, spell_family: 6, family_flags_0: 0x8000}},
            %{context() | spell: %Spell{id: 20_473, spell_family: 10, family_flags_0: 0x200000}},
            %{context() | proc_type: :deal_harmful_spell},
            %{context() | proc_type: :deal_helpful_periodic},
            %{context() | outcome: :resist},
            %{context() | outcome: :cast_end},
            %{context() | victim_alive?: false}
          ] do
        assert {^healer, []} = Aura.reactions(healer, :spell_hit_dealt, invalid)
      end
    end

    test "feedback retains the target class and permits self-healing and overhealing", %{healer: healer} do
      for {victim, class, expected} <- [{1, 2, 28_795}, {2, 8, 28_793}] do
        context = %{context() | victim_guid: victim, victim_class: class, damage: 0}
        updated = SpellFeedback.receive(healer, Map.delete(context, :spell), context.spell, 1_000)
        assert [%Effects.TriggerSpell{spell_id: ^expected, target_guid: ^victim}] = updated.internal.events
        assert updated.unit.health == healer.unit.health
      end
    end
  end

  defp healer(_context) do
    %{
      healer: %Mob{
        object: %Object{guid: 1},
        unit: %Unit{class: 2, level: 60, health: 100, max_health: 100, auras: [holder(28_789)]},
        internal: %Internal{}
      }
    }
  end

  defp holder(id) do
    %Holder{
      spell: %Spell{
        id: id,
        proc_type_mask: 0x4000,
        proc_chance: 100,
        proc_rule: %ProcRule{spell_family: 10, family_mask_0: 0xC0006000, cooldown_ms: 1_000}
      },
      caster_guid: 1,
      caster_level: 60,
      cast_item_guid: 99,
      auras: [%AuraData{type: :dummy}],
      charges: 2
    }
  end

  defp context do
    %{
      spell: %Spell{id: 635, spell_family: 10, family_flags_0: 0x80000000},
      victim_guid: 2,
      victim_alive?: true,
      victim_class: 8,
      victim_power_type: 0,
      proc_type: :deal_helpful_spell,
      outcome: :normal,
      damage: 10,
      now: 1_000
    }
  end
end
