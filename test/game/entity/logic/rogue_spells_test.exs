defmodule ThistleTea.Game.Entity.Logic.RogueSpellsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Reactive
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.CastValidation
  alias ThistleTea.Game.Spell.Cooldowns
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Targets

  defp rogue(opts \\ []) do
    %Character{
      object: %Object{guid: 5},
      unit: %Unit{
        class: 4,
        level: 60,
        health: 1_000,
        max_health: 1_000,
        power_type: 3,
        power4: 100,
        max_power4: 100,
        shapeshift_form: 0,
        auras: [],
        flags: 0
      },
      player: %Player{flags: 0},
      internal: %Internal{in_combat: Keyword.get(opts, :in_combat, false)}
    }
  end

  defp target do
    %Character{
      object: %Object{guid: 9},
      unit: %Unit{level: 60, health: 1_000, max_health: 1_000, auras: [], flags: 0},
      player: %Player{},
      internal: %Internal{}
    }
  end

  describe "combo points" do
    test "builders accumulate to five on one target and reset when changing target" do
      entity = rogue() |> Reactive.add_combo_points(9, 2) |> Reactive.add_combo_points(9, 4)

      assert entity.player.field_combo_target == 9
      assert entity.player.combo_points == 5
      assert Reactive.combo_active?(entity, 9, 100_000)

      entity = Reactive.add_combo_points(entity, 10, 1)
      assert entity.player.field_combo_target == 10
      assert entity.player.combo_points == 1
    end

    test "finishers require points on their selected target" do
      eviscerate = %Spell{id: 6760, name: "Eviscerate", power_type: 3, mana_cost: 35}
      entity = Reactive.add_combo_points(rogue(), 9, 2)

      assert :ok = CastValidation.validate(entity, eviscerate, Targets.unit(9), nil, 1_000)

      assert {:error, :cant_do_that_yet} =
               CastValidation.validate(entity, eviscerate, Targets.unit(10), nil, 1_000)
    end

    test "eviscerate damage scales with the spent points" do
      spell = %Spell{
        id: 6760,
        name: "Eviscerate",
        school: :physical,
        effects: [%Effect{index: 0, type: :school_damage, base_points: 10, die_sides: 0}]
      }

      context = %CastContext{caster_guid: 5, caster_level: 60, combo_points: 4, spell: spell}
      {victim, _events} = SpellEffect.receive(target(), context, spell, 1_000)

      assert victim.unit.health == 960
    end
  end

  describe "stealth and vanish" do
    test "stealth sets the rogue form and breaks on a hostile cast" do
      stealth = %Spell{
        id: 1784,
        name: "Stealth",
        duration_ms: -1,
        aura_interrupt_flags: 0x3C07,
        effects: [%Effect{index: 0, type: :apply_aura, aura: :mod_stealth, base_points: 5}]
      }

      {entity, _events} = Aura.apply_spell(rogue(), 5, 60, stealth, 1_000)
      assert entity.unit.shapeshift_form == 30

      entity = Aura.break_on_damage(entity, 2_000)
      assert entity.unit.shapeshift_form == 0
      assert entity.unit.auras == []
    end

    test "ordinary stealth is unavailable in combat but vanish remains available" do
      stealth = %Spell{id: 1784, name: "Stealth"}
      vanish = %Spell{id: 1856, name: "Vanish"}

      assert {:error, :affecting_combat} =
               CastValidation.validate(rogue(in_combat: true), stealth, %Targets{}, nil, 1_000)

      assert :ok = CastValidation.validate(rogue(in_combat: true), vanish, %Targets{}, nil, 1_000)
    end

    test "cold blood forces the next melee ability to crit" do
      cold_blood = %Spell{
        id: 14_177,
        duration_ms: -1,
        effects: [%Effect{index: 0, type: :apply_aura, aura: :force_crit}]
      }

      {entity, _events} = Aura.apply_spell(rogue(), 5, 60, cold_blood, 1_000)
      context = CastContext.from_caster(entity, %Spell{dmg_class: 2}, 9)

      assert context.melee_crit_chance == 100.0
    end

    test "preparation resets core rogue cooldowns without resetting itself" do
      entity = rogue()

      internal = %{
        entity.internal
        | cooldowns: %{14_177 => 10_000, {:category, 39} => 10_000, {:category, 44} => 10_000, 14_185 => 20_000}
      }

      preparation = %Spell{id: 14_185, name: "Preparation", effects: [%Effect{index: 0, type: :dummy}]}
      context = %CastContext{caster_guid: 5, caster_level: 60, spell: preparation}
      {entity, _events} = SpellEffect.receive(%{entity | internal: internal}, context, preparation, 1_000)

      refute Cooldowns.on_cooldown?(entity, %Spell{id: 14_177}, 1_000)
      refute Cooldowns.on_cooldown?(entity, %Spell{id: 1856, category: 39}, 1_000)
      assert Cooldowns.on_cooldown?(entity, preparation, 1_000)
    end

    test "vanish purge removes roots and slows while granting temporary immunity" do
      root = %Spell{
        id: 100,
        duration_ms: 10_000,
        mechanic: 7,
        effects: [%Effect{index: 0, type: :apply_aura, aura: :mod_root}]
      }

      purge = %Spell{
        id: 18_461,
        duration_ms: 1_000,
        effects: [
          %Effect{index: 0, type: :apply_aura, aura: :mechanic_immunity, misc_value: 7},
          %Effect{index: 1, type: :apply_aura, aura: :mechanic_immunity, misc_value: 11}
        ]
      }

      {entity, _events} = Aura.apply_spell(rogue(), 9, 60, root, 1_000)
      {entity, _events} = Aura.apply_spell(entity, 5, 60, purge, 2_000)

      refute Aura.has_spell?(entity, 100)
      assert Aura.has_spell?(entity, 18_461)
      assert Aura.mechanic_immune?(entity, root)
    end

    test "vanish drops combat and asks every threatening mob to forget the rogue" do
      entity = rogue(in_combat: true)
      internal = %{entity.internal | threat_refs: MapSet.new([101, 102]), last_hostile_time: 900}
      entity = %{entity | internal: internal}
      vanish = %Spell{id: 1856, name: "Vanish", effects: [%Effect{index: 0, type: :clear_threat}]}
      context = %CastContext{caster_guid: 5, caster_level: 60, spell: vanish}

      {entity, events} = SpellEffect.receive(entity, context, vanish, 1_000)

      refute entity.internal.in_combat
      assert entity.internal.threat_refs == MapSet.new()
      assert Enum.sort(Enum.map(events, &{&1.type, &1.target_guid})) == [drop_threat: 101, drop_threat: 102]
    end
  end
end
