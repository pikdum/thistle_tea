defmodule ThistleTea.Game.World.Loader.SpellComboPointsDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AttackFeedback
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.ComboPoints
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  setup [:entities]

  describe "load/1" do
    test "critical builders produce one talent proc through one melee outcome", %{caster: caster, target: target} do
      for {builder_id, talent_id, trigger_id} <- [{1752, 14_195, 14_189}, {1082, 16_954, 16_953}] do
        spell = SpellLoader.load(builder_id)
        talent = SpellLoader.load(talent_id)
        {caster, _events} = Aura.apply_spell(caster, caster.object.guid, 60, talent, 0)
        context = melee_context(caster, spell)
        {_target, events} = SpellEffect.receive(target, context, spell, 1_000)
        assert [%Effects.AddComboPoints{amount: 1} = award] = awards(events)

        assert [%Effects.AttackOutcome{outcome: :crit} = outcome] =
                 Enum.filter(events, &is_struct(&1, Effects.AttackOutcome))

        assert Enum.all?(Enum.filter(events, &is_struct(&1, Effects.SpellDamage)), &is_nil(&1.proc_type))

        caster =
          caster
          |> ComboPoints.award(award, 1_000)
          |> AttackFeedback.receive(feedback(outcome), spell, 1_000)

        triggers = Enum.filter(caster.internal.events, &is_struct(&1, Effects.TriggerSpell))
        assert [%Effects.TriggerSpell{spell_id: ^trigger_id}] = triggers
      end
    end

    test "druid finishers consume points through their melee outcome", %{caster: caster, target: target} do
      spell = SpellLoader.load(1079)
      caster = ComboPoints.add(caster, target.object.guid, 3, 0)
      context = %{melee_context(caster, spell) | combo_points: 3}
      {_target, events} = SpellEffect.receive(target, context, spell, 1_000)
      assert [outcome] = Enum.filter(events, &is_struct(&1, Effects.AttackOutcome))
      assert AttackFeedback.receive(caster, feedback(outcome), spell, 1_000).player.combo_points == 0
    end

    test "Premeditation grants two points for ten seconds", %{caster: caster, target: target} do
      spell = SpellLoader.load(14_183)
      assert spell.dmg_class == 0
      assert spell.duration_ms == 10_000
      context = context(caster, spell)
      {_target, events} = SpellEffect.receive(target, context, spell, 1_000)
      assert [%Effects.AddComboPoints{amount: 2} = award] = awards(events)
      caster = ComboPoints.award(caster, award, 1_000)
      assert caster.player.combo_points == 2
      assert Aura.has_aura?(caster, :retain_combo_points)
      {caster, _events} = Aura.tick(caster, 11_000)
      assert caster.player.combo_points == 0
      refute Aura.has_aura?(caster, :retain_combo_points)
    end

    test "rogue and druid triggered builders grant one point", %{caster: caster, target: target} do
      for id <- [13_977, 14_157, 14_189, 15_250, 16_953] do
        spell = SpellLoader.load(id)
        assert spell.dmg_class == 0
        {_target, events} = SpellEffect.receive(target, %{context(caster, spell) | triggered?: true}, spell, 1_000)
        assert [%Effects.AddComboPoints{amount: 1, retention: nil} = award] = awards(events)
        assert ComboPoints.award(caster, award, 1_000).player.combo_points == 1
      end
    end
  end

  defp awards(events), do: Enum.filter(events, &is_struct(&1, Effects.AddComboPoints))

  defp feedback(outcome) do
    %{outcome: outcome.outcome, victim_guid: outcome.source_guid, spell_id: outcome.spell_id, damage: outcome.damage}
  end

  defp melee_context(caster, spell) do
    %{
      context(caster, spell)
      | hit_chance_bonus: 100,
        attack_skill: 300,
        melee_crit_chance: 100,
        weapon_base_min: 1,
        weapon_base_max: 1,
        attack_time_ms: 2_000,
        normalized_speed: 2.4,
        attack_power: 0
    }
  end

  defp context(caster, spell) do
    %CastContext{
      caster_guid: caster.object.guid,
      caster_type: :player,
      caster_level: 60,
      spell: spell,
      target_role: :other
    }
  end

  defp entities(_context) do
    caster = %Character{
      object: %Object{guid: 5},
      unit: %Unit{class: 4, level: 60, health: 100, max_health: 100, auras: []},
      player: %Player{flags: 0},
      internal: %Internal{}
    }

    target = %Mob{object: %Object{guid: 9}, unit: %Unit{level: 1, health: 10_000, max_health: 10_000, auras: []}}
    %{caster: caster, target: target}
  end
end
