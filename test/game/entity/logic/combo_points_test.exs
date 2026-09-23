defmodule ThistleTea.Game.Entity.Logic.ComboPointsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AttackFeedback
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.ComboPoints
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Reactive
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect

  setup [:entities]

  describe "award/3" do
    test "temporary points expire without removing earlier points", %{rogue: rogue, target: target} do
      rogue = ComboPoints.add(rogue, target.object.guid, 1, 0)
      rogue = award(rogue, target, premeditation(), 1_000)
      assert rogue.player.combo_points == 3
      assert rogue.player.field_combo_target == target.object.guid
      assert Aura.has_aura?(rogue, :retain_combo_points)
      {rogue, _events} = Aura.tick(rogue, 10_999)
      assert rogue.player.combo_points == 3
      {rogue, _events} = Aura.tick(rogue, 11_000)
      assert rogue.player.combo_points == 1
      refute Aura.has_aura?(rogue, :retain_combo_points)
    end

    test "a later builder makes temporary points permanent even at the cap", %{rogue: rogue, target: target} do
      rogue = ComboPoints.add(rogue, target.object.guid, 4, 0)
      rogue = award(rogue, target, premeditation(), 1_000)
      assert rogue.player.combo_points == 5
      rogue = award(rogue, target, builder(), 2_000)
      refute Aura.has_aura?(rogue, :retain_combo_points)
      {rogue, _events} = Aura.tick(rogue, 11_000)
      assert rogue.player.combo_points == 5
    end

    test "expiry subtracts the aura amount at the point cap", %{rogue: rogue, target: target} do
      rogue = rogue |> ComboPoints.add(target.object.guid, 4, 0) |> award(target, premeditation(), 1_000)
      {rogue, _events} = Aura.tick(rogue, 11_000)
      assert rogue.player.combo_points == 3
    end

    test "changing builder targets drops old points and their timer", %{rogue: rogue, target: target} do
      rogue = award(rogue, target, premeditation(), 1_000)
      other = %{target | object: %Object{guid: 11}}
      rogue = award(rogue, other, builder(), 2_000)
      {rogue, _events} = Aura.tick(rogue, 11_000)
      assert rogue.player.combo_points == 1
      assert rogue.player.field_combo_target == 11
      refute Aura.has_aura?(rogue, :retain_combo_points)
    end

    test "successful finishers spend temporary points and avoidance preserves them", %{rogue: rogue, target: target} do
      rogue = award(rogue, target, premeditation(), 1_000)
      finisher = %Spell{id: 6760, attributes: MapSet.new([:finishing_move])}
      payload = %{outcome: :dodge, victim_guid: target.object.guid, damage: 0}
      avoided = AttackFeedback.receive(rogue, payload, finisher, 2_000)
      assert avoided.player.combo_points == 2
      assert Aura.has_aura?(avoided, :retain_combo_points)
      landed = AttackFeedback.receive(rogue, %{payload | outcome: :normal}, finisher, 2_000)
      assert landed.player.combo_points == 0
      refute Aura.has_aura?(landed, :retain_combo_points)
      refute Reactive.combo_active?(landed, target.object.guid, 2_000)
      {landed, _events} = Aura.tick(landed, 11_000)
      assert landed.player.combo_points == 0
    end

    test "cancellation does not subtract points", %{rogue: rogue, target: target} do
      rogue = award(rogue, target, premeditation(), 1_000)
      {rogue, _events} = Aura.remove_aura_types(rogue, [:retain_combo_points], 2_000)
      {rogue, _events} = Aura.tick(rogue, 11_000)
      assert rogue.player.combo_points == 2
    end

    test "death clears points and rejects delayed awards", %{rogue: rogue, target: target} do
      rogue = award(rogue, target, premeditation(), 1_000)
      dead = Core.take_damage(rogue, 1_000, 2_000)
      assert dead.player.combo_points == 0
      refute Aura.has_aura?(dead, :retain_combo_points)
      award = %Effects.AddComboPoints{source_guid: rogue.object.guid, target_guid: target.object.guid, amount: 1}
      assert ComboPoints.award(dead, award, 3_000) == dead
      ghost = %{dead | unit: %{dead.unit | health: 1}, player: %{dead.player | flags: 0x10}}
      assert ComboPoints.award(ghost, award, 3_000) == ghost
    end

    test "target death removes the retention timer", %{rogue: rogue, target: target} do
      rogue = award(rogue, target, premeditation(), 1_000)
      rogue = Reactive.clear_combo_target(rogue, target.object.guid)
      assert rogue.player.combo_points == 0
      assert rogue.internal.combo_target_guid == nil
      refute Aura.has_aura?(rogue, :retain_combo_points)
    end
  end

  describe "SpellEffect.receive/4" do
    test "non-melee builders award the caster after resolving the target", %{rogue: rogue, target: target} do
      spell = premeditation()
      context = context(rogue, spell)
      {unchanged, caster_events} = SpellEffect.receive(rogue, %{context | target_role: :caster}, spell, 1_000)
      refute Aura.has_aura?(unchanged, :retain_combo_points)
      refute Enum.any?(caster_events, &is_struct(&1, Effects.AddComboPoints))
      {unchanged, events} = SpellEffect.receive(target, context, spell, 1_000)
      assert unchanged.unit.health == target.unit.health
      assert [%Effects.AddComboPoints{source_guid: 5, target_guid: 9, amount: 2}] = awards(events)
      refute Aura.has_aura?(unchanged, :retain_combo_points)
    end

    test "resisted and dead targets grant neither points nor retention", %{rogue: rogue, target: target} do
      spell = premeditation()
      context = context(rogue, spell)
      {_target, events} = SpellEffect.receive(target, %{context | hit_outcome: :resist}, spell, 1_000)
      assert awards(events) == []
      dead = %{target | unit: %{target.unit | health: 0}}
      {_target, events} = SpellEffect.receive(dead, context, spell, 1_000)
      assert awards(events) == []
    end

    test "melee builders award only on a landed effect", %{rogue: rogue, target: target} do
      spell = %{
        builder()
        | dmg_class: 2,
          effects: [%Effect{index: 1, type: :school_damage, base_points: 1} | builder().effects]
      }

      context = %{context(rogue, spell) | hit_chance_bonus: 100, attack_skill: 10_000, melee_crit_chance: 0}

      no_dodge = %Spell{
        id: 99_002,
        effects: [%Effect{index: 0, type: :apply_aura, aura: :mod_dodge, base_points: -1_000}]
      }

      {exposed, _events} = Aura.apply_spell(target, target.object.guid, 60, no_dodge, 1_000)
      {_target, events} = SpellEffect.receive(exposed, context, spell, 1_000)
      assert [%Effects.AddComboPoints{amount: 1}] = awards(events)
      dodge = %Spell{id: 99_001, effects: [%Effect{index: 0, type: :apply_aura, aura: :mod_dodge, base_points: 1_000}]}
      {target, _events} = Aura.apply_spell(target, target.object.guid, 60, dodge, 1_000)
      {_target, events} = SpellEffect.receive(target, %{context | attack_skill: 300}, spell, 1_000)
      assert awards(events) == []
    end

    test "creature builders never grant player points", %{rogue: rogue, target: target} do
      spell = builder()
      {_target, events} = SpellEffect.receive(target, %{context(rogue, spell) | caster_type: :mob}, spell, 1_000)
      assert awards(events) == []
    end
  end

  defp award(rogue, target, spell, now) do
    {_target, events} = SpellEffect.receive(target, context(rogue, spell), spell, now)
    [award] = awards(events)
    ComboPoints.award(rogue, award, now)
  end

  defp awards(events), do: Enum.filter(events, &is_struct(&1, Effects.AddComboPoints))

  defp context(rogue, spell) do
    %CastContext{
      caster_guid: rogue.object.guid,
      caster_level: 60,
      caster_type: :player,
      spell: spell,
      target_role: :other
    }
  end

  defp builder do
    %Spell{
      id: 14_157,
      effects: [%Effect{index: 0, type: :add_combo_points, base_points: 1, implicit_target_a: :target_enemy}]
    }
  end

  defp premeditation do
    %Spell{
      id: 14_183,
      duration_ms: 10_000,
      effects: [
        %Effect{index: 0, type: :add_combo_points, base_points: 2, implicit_target_a: :target_enemy},
        %Effect{index: 1, type: :apply_aura, aura: :retain_combo_points, base_points: 2, implicit_target_a: :caster}
      ]
    }
  end

  defp entities(_context) do
    rogue = %Character{
      object: %Object{guid: 5},
      unit: %Unit{
        class: 4,
        level: 60,
        health: 1_000,
        max_health: 1_000,
        power_type: 3,
        power4: 100,
        max_power4: 100,
        auras: []
      },
      player: %Player{flags: 0},
      internal: %Internal{},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    target = %Mob{
      object: %Object{guid: 9},
      unit: %Unit{level: 60, health: 1_000, max_health: 1_000, auras: []},
      internal: %Internal{},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    %{rogue: rogue, target: target}
  end
end
