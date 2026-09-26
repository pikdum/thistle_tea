defmodule ThistleTea.Game.Entity.Logic.DepletingAuraTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.AttackFeedback
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Aura.Change
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Skills
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Entity.Logic.SpellFeedback
  alias ThistleTea.Game.Entity.Logic.WeaponDamage
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Proc

  @pairs [{24_661, 24_662, 20}, {24_574, 24_575, 10}, {26_463, 26_464, 10}]
  @magic_resistances [:fire_resistance, :frost_resistance, :nature_resistance, :shadow_resistance, :arcane_resistance]

  setup [:character]

  describe "receive/4" do
    test "item spell chains initialize full bonuses and client stack counts", %{character: character} do
      for {parent, bonus, stacks} <- @pairs do
        buffed = cast(character, parent, 0)
        assert holder(buffed, parent)
        assert holder(buffed, bonus).stacks == stacks
        assert stack_byte(buffed, bonus) == stacks - 1
      end

      strength = cast(character, 24_661, 0)
      assert WeaponDamage.flat_bonus(strength, :physical, nil) == 40
      armor = cast(character, 24_574, 0)
      assert armor.unit.normal_resistance == 2_100
      assert Skills.defense_value(armor) == 330
      assert Skills.bonuses(armor) == %{95 => {30, 0}}
      shield = cast(character, 26_463, 0)
      assert shield.unit.fire_resistance == 100
      assert shield.unit.holy_resistance == 0
      assert shield.unit.normal_resistance == 100
    end

    test "Restless Strength spends once for each landed melee or ranged attack", %{character: character} do
      buffed = cast(character, 24_661, 0)

      for outcome <- [:normal, :crit, :glancing, :crushing, :block], hand <- [:mainhand, :offhand] do
        payload = %{victim_guid: 2, outcome: outcome, damage: 10, hand: hand, proc_ex: Proc.hit_mask(outcome, 10, 0)}
        spent = AttackFeedback.receive(buffed, payload, nil, 1_000)
        assert holder(spent, 24_662).stacks == 19
        assert WeaponDamage.flat_bonus(spent, :physical, nil) == 38
      end

      for {spell, type} <- [
            {attack_spell(2), :deal_melee_ability},
            {attack_spell(3), :deal_ranged_ability},
            {attack_spell(3), :deal_ranged_attack}
          ] do
        payload = %{victim_guid: 2, outcome: :normal, damage: 10, proc_type: type}
        spent = SpellFeedback.receive(buffed, payload, spell, 1_000)
        assert holder(spent, 24_662).stacks == 19
      end

      exhausted =
        Enum.reduce(1..20, buffed, fn hit, current ->
          spent = AttackFeedback.receive(current, %{victim_guid: 2, outcome: :normal, damage: 10}, nil, hit * 500)
          assert WeaponDamage.flat_bonus(spent, :physical, nil) == (20 - hit) * 2
          spent
        end)

      refute holder(exhausted, 24_662)
      assert holder(exhausted, 24_661)
      spent = AttackFeedback.receive(exhausted, %{victim_guid: 2, outcome: :normal, damage: 10}, nil, 11_000)
      refute holder(spent, 24_662)
      assert holder(cast(spent, 24_661, 12_000), 24_662).stacks == 20
    end

    test "Restless Strength ignores avoided attacks, magic and periodic feedback", %{character: character} do
      buffed = cast(character, 24_661, 0)

      for outcome <- [:miss, :dodge, :parry, :block, :immune] do
        payload = %{victim_guid: 2, outcome: outcome, damage: 0, proc_ex: Proc.hit_mask(outcome, 0, 0)}
        unchanged = AttackFeedback.receive(buffed, payload, nil, 1_000)
        assert holder(unchanged, 24_662).stacks == 20
      end

      for {type, outcome} <- [
            {:deal_harmful_spell, :normal},
            {:deal_harmful_periodic, :normal},
            {:deal_helpful_spell, :normal},
            {:deal_ranged_ability, :cast_end}
          ] do
        unchanged =
          SpellFeedback.receive(buffed, %{victim_guid: 2, proc_type: type, outcome: outcome}, attack_spell(1), 1_000)

        assert holder(unchanged, 24_662).stacks == 20
      end
    end

    test "incoming hits deplete armor and defense together without refreshing the deadline", %{character: character} do
      buffed = cast(character, 24_574, 0)

      exhausted =
        Enum.reduce(1..10, buffed, fn hit, current ->
          spent = incoming(current, :hit_taken, :take_ranged_attack, :normal, hit * 500)
          assert spent.unit.normal_resistance == 100 + (10 - hit) * 200
          assert Skills.defense_value(spent) == 300 + (10 - hit) * 3

          if hit < 10 do
            assert holder(spent, 24_575).expires_at == 20_000
            assert stack_byte(spent, 24_575) == 9 - hit
          end

          spent
        end)

      refute holder(exhausted, 24_575)
      assert holder(exhausted, 24_574)
      assert incoming(exhausted, :hit_taken, :take_melee_swing, :normal, 6_000).unit.normal_resistance == 100

      for outcome <- [:miss, :dodge, :parry, :block] do
        unchanged = incoming(buffed, :hit_taken, :take_melee_swing, outcome, 1_000)
        assert holder(unchanged, 24_575).stacks == 10
      end

      unchanged = incoming(buffed, :spell_hit_taken, :take_harmful_spell, :normal, 1_000)
      assert holder(unchanged, 24_575).stacks == 10
    end

    test "Mercurial Shield depletes on harmful hits and debuffs", %{character: character} do
      buffed = cast(character, 26_463, 0)

      exhausted =
        Enum.reduce(1..10, buffed, fn hit, current ->
          spent = incoming(current, :spell_hit_taken, :take_harmful_spell, :normal, hit * 500)

          for field <- @magic_resistances do
            assert Map.fetch!(spent.unit, field) == (10 - hit) * 10
          end

          spent
        end)

      refute holder(exhausted, 26_464)
      assert holder(exhausted, 26_463)

      for {event, type, outcome} <- [
            {:spell_hit_taken, :take_harmful_spell, :resist},
            {:spell_hit_taken, :take_harmful_periodic, :normal},
            {:hit_taken, :take_melee_swing, :normal}
          ] do
        unchanged = incoming(buffed, event, type, outcome, 1_000)
        assert holder(unchanged, 26_464).stacks == 10
      end
    end
  end

  describe "transition/2" do
    test "source removal, expiry and death clean every linked bonus", %{character: character} do
      for {parent, bonus, _stacks} <- @pairs do
        buffed = cast(character, parent, 0)
        {spent, _} = Aura.remove_stack(buffed, bonus, 1_000)
        assert holder(spent, bonus).expires_at == holder(buffed, bonus).expires_at

        for cause <- Change.causes() -- [:applied, :ticked, :delayed] do
          kept = Enum.reject(spent.unit.auras, &(&1.spell.id == parent))
          {removed, _} = Aura.transition(spent, %Change{holders: kept, cause: cause, now: 1_500})
          assert removed.unit.auras == []
          assert Skills.defense_value(removed) == 300
          assert removed.unit.normal_resistance == 100
        end

        deadline = buff(parent).duration_ms
        {expired, _} = Aura.tick(spent, deadline)
        assert expired.unit.auras == []
        assert Core.take_damage(spent, 100, 1_500).unit.auras == []
        assert holder(cast(spent, parent, 2_000), bonus).expires_at == deadline + 2_000
      end
    end

    test "late bonus deliveries cannot recreate missing or expired sources", %{character: character} do
      for {parent, bonus, _stacks} <- @pairs do
        assert cast(character, bonus, 0).unit.auras == []
        {buffed, _} = Aura.apply_spell(character, 1, 60, buff(parent), 0)
        delivered = cast(buffed, bonus, buff(parent).duration_ms)
        refute holder(delivered, bonus)
      end
    end
  end

  defp incoming(character, event, type, outcome, now) do
    context = %{attacker_guid: 2, spell: attack_spell(1), proc_type: type, outcome: outcome, damage: 0, now: now}
    {character, events} = Aura.reactions(character, event, context)
    deliver(character, events, now)
  end

  defp cast(character, id, now) do
    context = %CastContext{caster_guid: 1, caster_level: 60, target_guid: 1, target_role: :self}
    {character, events} = SpellEffect.receive(character, context, buff(id), now)
    deliver(character, events, now)
  end

  defp deliver(character, events, now) do
    Enum.reduce(events, character, fn
      %Effects.TriggerSpell{spell_id: id}, current -> cast(current, id, now)
      _event, current -> current
    end)
  end

  defp holder(character, id), do: Enum.find(character.unit.auras, &(&1.spell.id == id))
  defp stack_byte(character, id), do: :binary.at(character.unit.aura_applications, holder(character, id).slot)

  defp attack_spell(class),
    do: %Spell{id: 100, dmg_class: class, school: :physical, effects: [%Effect{type: :school_damage}]}

  defp character(_context) do
    %{
      character: %Character{
        object: %Object{guid: 1},
        player: %Player{},
        internal: %Internal{},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        unit: %Unit{
          health: 100,
          max_health: 100,
          level: 60,
          class: 8,
          auras: [],
          normal_resistance: 100,
          base_normal_resistance: 100,
          base_holy_resistance: 0,
          base_fire_resistance: 0,
          base_nature_resistance: 0,
          base_frost_resistance: 0,
          base_shadow_resistance: 0,
          base_arcane_resistance: 0
        }
      }
    }
  end

  defp buff(id) do
    %Spell{id: id, duration_ms: if(id in [26_463, 26_464], do: 60_000, else: 20_000), proc_chance: 100}
    |> buff_effects(id)
  end

  defp buff_effects(spell, 24_661), do: %{spell | proc_type_mask: 0x154, effects: [aura(:dummy, 0, 0)]}
  defp buff_effects(spell, 24_662), do: %{spell | stack_amount: 20, effects: [aura(:mod_damage_done, 2, 1)]}

  defp buff_effects(spell, 24_574),
    do: %{
      spell
      | proc_type_mask: 0x2A8,
        effects: [
          %{aura(:proc_trigger_spell, 0, 0) | trigger_spell_id: 24_590},
          %Effect{index: 1, type: :trigger_spell, trigger_spell_id: 29_284, implicit_target_a: 1}
        ]
    }

  defp buff_effects(spell, 24_575),
    do: %{spell | stack_amount: 10, effects: [aura(:mod_resistance, 200, 1), %{aura(:mod_skill, 3, 95) | index: 1}]}

  defp buff_effects(spell, 26_463),
    do: %{
      spell
      | proc_type_mask: 0x20000,
        effects: [
          %{aura(:proc_trigger_spell, 0, 0) | trigger_spell_id: 26_465},
          %Effect{index: 1, type: :trigger_spell, trigger_spell_id: 29_286, implicit_target_a: 1}
        ]
    }

  defp buff_effects(spell, 26_464), do: %{spell | stack_amount: 10, effects: [aura(:mod_resistance, 10, 124)]}

  defp buff_effects(spell, id) when id in [24_590, 26_465],
    do: %{spell | effects: [%Effect{index: 0, type: :script_effect}]}

  defp buff_effects(spell, id) do
    name = if id == 29_284, do: "spell_brittle_armor_dummy", else: "spell_mercurial_shield_dummy"
    %{spell | script_name: name, effects: [%Effect{index: 0, type: :dummy}]}
  end

  defp aura(type, amount, misc),
    do: %Effect{index: 0, type: :apply_aura, aura: type, base_points: amount, misc_value: misc}
end
