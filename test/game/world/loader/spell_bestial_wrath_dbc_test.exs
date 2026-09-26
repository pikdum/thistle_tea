defmodule ThistleTea.Game.World.Loader.SpellBestialWrathDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db
  @boosts [24_395, 24_396, 24_397, 26_592]

  setup [:pet_and_spells]

  describe "load/1" do
    test "preloads all control-immunity boosts with their original flags", %{wrath: wrath} do
      assert wrath.duration_ms == 18_000
      assert Enum.map(wrath.boost_auras, & &1.id) == @boosts
      assert SpellLoader.build_spellbook([wrath.id])[wrath.id] == wrath

      assert Enum.map(wrath.boost_auras, fn spell -> Enum.map(spell.effects, & &1.misc_value) end) ==
               [[1, 5, 17], [14, 13, 24], [7, 10, 11], [2]]

      for spell <- wrath.boost_auras do
        assert Spell.attribute?(spell, :immunity_purges_effect)
        refute Spell.attribute?(spell, :passive)
        assert Enum.all?(spell.effects, &(&1.aura == :mechanic_immunity))
      end
    end
  end

  describe "apply_spell/5" do
    test "cleanses existing control while preserving damage and scale bonuses", %{pet: pet, wrath: wrath} do
      for id <- [118, 122, 853, 5782, 2094, 3355] do
        control = SpellLoader.load(id)
        {controlled, _} = Aura.apply_spell(pet, 3, 50, control, 0)
        assert Aura.has_spell?(controlled, id)
        {protected, _} = Aura.apply_spell(controlled, 1, 50, wrath, 1_000)
        refute Aura.has_spell?(protected, id)
        assert protected.object.scale_x == 1.5
        assert Aura.percent_multiplier(protected, :mod_damage_percent_done, 1) == 1.5
        refute protected.internal.rooted?
        assert Enum.map(protected.unit.auras, & &1.spell.id) == [wrath.id | @boosts]
        [parent | children] = protected.unit.auras

        for child <- children do
          assert child.caster_guid == 1
          assert child.linked_from == {Holder.key(parent), 1_000}
        end
      end
    end
  end

  describe "receive/4" do
    test "blocks whole-spell controls with one immune result", %{pet: pet, wrath: wrath} do
      {protected, _} = Aura.apply_spell(pet, 1, 50, wrath, 1_000)

      for id <- [118, 853, 5782, 2094, 3355] do
        spell = SpellLoader.load(id)
        context = %CastContext{caster_guid: 3, caster_level: 50, spell: spell, target_hostile?: true}
        {received, events} = SpellEffect.receive(protected, context, spell, 2_000)
        refute Aura.has_spell?(received, id)
        assert received.unit.health == protected.unit.health
        assert [%Effects.SpellLogMiss{spell_id: ^id, reason: :immune}] = events
      end
    end

    test "blocks Frost Nova's root while allowing its damage", %{pet: pet, wrath: wrath} do
      {protected, _} = Aura.apply_spell(pet, 1, 50, wrath, 1_000)
      frost_nova = SpellLoader.load(122)
      context = %CastContext{caster_guid: 3, caster_level: 50, spell: frost_nova, target_hostile?: true}
      {damaged, events} = SpellEffect.receive(protected, context, frost_nova, 2_000)
      assert damaged.unit.health < protected.unit.health
      refute Aura.has_aura?(damaged, :mod_root)
      refute damaged.internal.rooted?
      assert Enum.any?(events, &is_struct(&1, Effects.SpellDamage))
      refute Enum.any?(events, &is_struct(&1, Effects.SpellLogMiss))
    end
  end

  describe "expire_due/2" do
    test "expiry clears every boost and permits control again", %{pet: pet, wrath: wrath} do
      {protected, _} = Aura.apply_spell(pet, 1, 50, wrath, 1_000)
      {expired, _} = Aura.expire_due(protected, 19_000)
      assert expired.unit.auras == []
      assert expired.object.scale_x == 1.0
      assert Aura.percent_multiplier(expired, :mod_damage_percent_done, 1) == 1.0
      {controlled, _} = Aura.apply_spell(expired, 3, 50, SpellLoader.load(118), 20_000)
      assert Aura.has_spell?(controlled, 118)
    end
  end

  describe "take_damage/4" do
    test "death clears the boosts and restores scale", %{pet: pet, wrath: wrath} do
      {protected, _} = Aura.apply_spell(pet, 1, 50, wrath, 1_000)
      dead = Core.take_damage(protected, 2_000, 2_000, school: :fire)
      assert dead.unit.health == 0
      assert dead.unit.auras == []
      assert dead.object.scale_x == 1.0
    end
  end

  defp pet_and_spells(_context) do
    pet = %Mob{
      object: %Object{guid: 2, scale_x: 1.0, base_scale_x: 1.0},
      unit: %Unit{level: 49, health: 1_000, max_health: 1_000, display_id: 247, native_display_id: 247, auras: []},
      internal: %Internal{pet: %Pet{owner_guid: 1, kind: :hunter_pet}},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}, movement_flags: 0}
    }

    %{pet: pet, wrath: SpellLoader.load(19_574)}
  end
end
