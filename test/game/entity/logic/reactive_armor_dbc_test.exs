defmodule ThistleTea.Game.Entity.Logic.ReactiveArmorDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.DBC
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.EffectResolver.Spells
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.EquipmentAuras
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Proc
  alias ThistleTea.Game.Spell.ProcRule
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @obsidian 27_539
  @adaptive 28_764
  @absorbs [27_533, 27_534, 27_535, 27_536, 27_538, 27_540]
  @resistances [28_765, 28_766, 28_768, 28_769, 28_770]
  @moduletag :dbc_db

  setup [:character]

  describe "load/1" do
    test "real equipment procs retain their chances and school-specific effects" do
      for {id, chance} <- [{@obsidian, 30}, {@adaptive, 20}] do
        spell = SpellLoader.load(id)
        assert spell.proc_chance == chance
        assert spell.proc_type_mask == 0x20000
        assert [%{aura: :dummy}] = spell.effects
        assert Proc.roll?(spell, nil, fn -> chance / 100 end)
        refute Proc.roll?(spell, nil, fn -> (chance + 1) / 100 end)
      end

      set = DBC.get(ItemSet, 526)
      assert set.set_spell_3 == @adaptive
      assert set.set_threshold_3 == 4

      for id <- @absorbs do
        spell = SpellLoader.load(id)
        assert spell.duration_ms == 6_000
        assert [%{aura: :school_absorb, base_points: 299, die_sides: 201}] = spell.effects
      end

      for id <- @resistances do
        spell = SpellLoader.load(id)
        assert spell.duration_ms == 30_000
        assert [%{aura: :mod_resistance, base_points: 34, die_sides: 1}] = spell.effects
      end
    end
  end

  describe "receive/4" do
    test "Obsidian Armor rolls its shield after damage and absorbs only its school", %{character: character} do
      character = equip(character, @obsidian)
      hit = SpellLoader.load(2136)

      context = %CastContext{
        caster_guid: 2,
        caster_level: 60,
        target_hostile?: true,
        hit_outcome: :hit,
        spell_crit_chance: 0
      }

      {damaged, events} = SpellEffect.receive(character, context, hit, 1_000)
      assert damaged.unit.health < character.unit.health
      assert [%Effects.TriggerSpell{spell_id: 27_533, cast_item_guid: 99} = proc] = triggers(events)
      shielded = deliver(damaged, proc, 1_000)
      assert shielded.unit.health == damaged.unit.health
      capacity = absorb(shielded)
      assert capacity in 300..500

      {wrong_school, absorbed} = Core.take_damage_with_absorb(shielded, 50, 2_000, school: :frost)
      assert absorbed == 0
      assert wrong_school.unit.health == shielded.unit.health - 50
      assert absorb(wrong_school) == capacity
      {partial, absorbed} = Core.take_damage_with_absorb(wrong_school, 125, 3_000, school: :fire)
      assert absorbed == 125
      assert partial.unit.health == wrong_school.unit.health
      assert absorb(partial) == capacity - 125
      {depleted, absorbed} = Core.take_damage_with_absorb(partial, capacity, 4_000, school: :fire)
      assert absorbed == capacity - 125
      assert depleted.unit.health == partial.unit.health - 125
      refute Enum.any?(depleted.unit.auras, &(&1.spell.id in @absorbs))

      {expired, _events} = Aura.expire_due(shielded, 7_000)
      refute Enum.any?(expired.unit.auras, &(&1.spell.id in @absorbs))
      assert Enum.find(expired.unit.auras, &(&1.spell.id == @obsidian)).next_proc_at == 11_000
    end

    test "every Mage Armor rank enables the correct resistance and expiry restores the baseline", %{
      character: character
    } do
      for armor_id <- [6117, 22_782, 22_783] do
        character = equip(character, @adaptive)
        {armored, _} = Aura.apply_spell(character, 1, 60, SpellLoader.load(armor_id), 0)

        for {school, field, expected} <- [
              {:fire, :fire_resistance, 28_765},
              {:nature, :nature_resistance, 28_768},
              {:frost, :frost_resistance, 28_766},
              {:shadow, :shadow_resistance, 28_769},
              {:arcane, :arcane_resistance, 28_770}
            ] do
          {reacted, [proc]} = react(armored, school, 1_000)
          assert proc.spell_id == expected
          buffed = deliver(reacted, proc, 1_000)
          assert Map.fetch!(buffed.unit, field) == Map.fetch!(armored.unit, field) + 35
          {expired, _} = Aura.expire_due(buffed, 31_000)
          assert Map.fetch!(expired.unit, field) == Map.fetch!(armored.unit, field)
        end
      end
    end

    test "removing equipment prevents new procs but lets an existing ward expire", %{character: character} do
      for id <- [@obsidian, @adaptive] do
        character = equip(character, id)
        {character, _} = Aura.apply_spell(character, 1, 60, SpellLoader.load(22_783), 0)
        {reacted, [proc]} = react(character, :fire, 1_000)
        buffed = deliver(reacted, proc, 1_000)
        removed = EquipmentAuras.sync(buffed, [], &SpellLoader.load/1, 2_000)
        refute Enum.any?(removed.unit.auras, &(&1.spell.id == id))
        assert Enum.any?(removed.unit.auras, &(&1.spell.id == proc.spell_id))
        assert {_, []} = react(removed, :fire, 12_000)
        dead = Core.take_damage(removed, 10_000, 13_000)
        assert dead.unit.health == 0
        refute Enum.any?(dead.unit.auras, &(&1.spell.id == proc.spell_id))
        assert Spells.resolve(dead, proc) == []
      end
    end

    test "cancelling Mage Armor stops further warding without erasing the active resistance", %{character: character} do
      character = equip(character, @adaptive)
      assert {_, []} = react(character, :fire, 1_000)
      {armored, _} = Aura.apply_spell(character, 1, 60, SpellLoader.load(22_783), 0)
      {reacted, [proc]} = react(armored, :fire, 1_000)
      buffed = deliver(reacted, proc, 1_000)
      {removed, _} = Aura.cancel_spell(buffed, 22_783, 2_000)
      assert removed.unit.fire_resistance == 35
      assert {_, []} = react(removed, :fire, 12_000)
      {expired, _} = Aura.expire_due(removed, 31_000)
      assert expired.unit.fire_resistance == 0
    end
  end

  defp triggers(events), do: Enum.filter(events, &is_struct(&1, Effects.TriggerSpell))

  defp absorb(character) do
    character.unit.auras |> Enum.flat_map(& &1.auras) |> Enum.find(&(&1.type == :school_absorb)) |> Map.fetch!(:amount)
  end

  defp deliver(character, event, now) do
    [delivery] = character |> Spells.resolve(event) |> Enum.filter(&is_struct(&1, Effects.DeliverSpell))
    assert delivery.target_guid == character.object.guid
    {character, _events} = SpellEffect.receive(character, delivery.cast_context, delivery.spell, now)
    character
  end

  defp react(character, school, now) do
    {character, events} =
      Aura.reactions(character, :spell_hit_taken, %{
        attacker_guid: 2,
        spell: %Spell{id: 133, school: school, dmg_class: 1},
        proc_type: :take_harmful_spell,
        outcome: :normal,
        damage: 20,
        now: now
      })

    {character, triggers(events)}
  end

  defp equip(character, id) do
    source = if id == @obsidian, do: {:item_equip, 99, id}, else: {:item_set, 526, id}
    get_spell = fn id -> %{SpellLoader.load(id) | proc_chance: 100, proc_rule: %ProcRule{cooldown_ms: 10_000}} end
    character |> EquipmentAuras.sync([], get_spell, 0, [source]) |> Effects.drain() |> elem(0)
  end

  defp character(_context) do
    book = Map.new(@absorbs ++ @resistances, &{&1, SpellLoader.load(&1)})

    character = %Character{
      object: %Object{guid: 1},
      player: %Player{},
      internal: %Internal{spellbook: book},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      unit: %Unit{
        level: 60,
        class: 8,
        health: 1000,
        max_health: 1000,
        base_fire_resistance: 0,
        base_frost_resistance: 0,
        base_shadow_resistance: 0,
        base_nature_resistance: 0,
        base_arcane_resistance: 0
      }
    }

    %{character: character}
  end
end
