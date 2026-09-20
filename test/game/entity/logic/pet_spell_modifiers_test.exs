defmodule ThistleTea.Game.Entity.Logic.PetSpellModifiersTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Companion.EntityRef
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.PetSpellModifiers
  alias ThistleTea.Game.Entity.Logic.PetTraining
  alias ThistleTea.Game.Entity.Logic.Stats
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Modifiers

  setup [:build_pet]

  describe "sync/4" do
    test "updates existing passives on rank replacement and removal without stacking", %{pet: pet} do
      first = PetSpellModifiers.sync(pet, 1, [modifier(3)], 1)
      assert first.unit.max_health == 1_030
      upgraded = PetSpellModifiers.sync(first, 1, [modifier(15)], 2)
      assert upgraded.unit.max_health == 1_150
      assert length(upgraded.unit.auras) == 1
      assert PetSpellModifiers.sync(upgraded, 1, [modifier(15)], 3) == upgraded
      reset = PetSpellModifiers.sync(upgraded, 1, [], 4)
      assert reset.unit.max_health == 1_000
      assert Enum.map(reset.unit.auras, & &1.caster_guid) == [2]
      assert reset.internal.pet.owner_spell_modifiers == []
    end

    test "rejects stale owners and respects spell family and mask", %{pet: pet} do
      assert PetSpellModifiers.sync(pet, 99, [modifier(15)], 1) == pet
      wrong_family = %{modifier(15) | spell: %Spell{id: 101, spell_family: 5}}
      assert PetSpellModifiers.sync(pet, 1, [wrong_family], 1).unit.max_health == 1_000
      unrelated = %{modifier(15) | auras: [%{hd(modifier(15).auras) | class_mask: 2}]}
      assert PetSpellModifiers.sync(pet, 1, [unrelated], 1).unit.max_health == 1_000
    end

    test "does not refresh temporary or externally cast auras", %{pet: pet} do
      [holder] = pet.unit.auras

      for untouched <- [%{holder | caster_guid: 9}, %{holder | expires_at: 1_000}] do
        altered = %{pet | unit: %{pet.unit | auras: [untouched]}}
        assert PetSpellModifiers.sync(altered, 1, [modifier(15)], 1).unit.auras == [untouched]
      end
    end

    test "does not resurrect a dead pet", %{pet: pet} do
      dead = %{pet | unit: %{pet.unit | health: 0}}
      updated = PetSpellModifiers.sync(dead, 1, [modifier(15)], 1)
      assert updated.unit.health == 0
      assert updated.unit.max_health == 1_150
    end
  end

  describe "restore_passives/2" do
    test "applies inherited modifiers when rebuilding a pet", %{pet: pet} do
      control = %{pet.internal.pet | owner_spell_modifiers: [modifier(15)]}
      pet = %{pet | unit: %{pet.unit | auras: []}, internal: %{pet.internal | pet: control}}
      restored = PetTraining.restore_passives(pet, 1)
      assert restored.unit.max_health == 1_150
      assert Modifiers.value(restored, hd(restored.unit.auras).spell, :all_effects, 0) == 15
    end
  end

  describe "aura transitions" do
    test "publishes owner modifier application and removal for the active pet" do
      owner = %Character{
        object: %Object{guid: 1},
        unit: %Unit{level: 50, health: 100, auras: []},
        internal: %Internal{}
      }

      owner = Companion.activate(owner, :hunter_pet, %EntityRef{guid: 2, entry: 1, spell_id: 883})

      spell = %Spell{
        id: 10,
        spell_family: 9,
        duration_ms: -1,
        effects: [
          %Effect{
            type: :apply_aura,
            aura: :add_flat_modifier,
            misc_value: 8,
            class_mask: 1,
            base_points: 14,
            die_sides: 1,
            base_dice: 1
          }
        ]
      }

      {learned, events} = Aura.apply_spell(owner, 1, 50, spell, 0)

      assert [%Effects.PetSpellModifiers{source_guid: 1, target_guid: 2, holders: [_]}] =
               Enum.filter(events, &match?(%Effects.PetSpellModifiers{}, &1))

      {_reset, events} = Aura.remove_spells(learned, [10], 1)
      assert %Effects.PetSpellModifiers{source_guid: 1, target_guid: 2, holders: []} in events
    end
  end

  defp build_pet(_context) do
    spell = %Spell{
      id: 100,
      attributes: MapSet.new([:passive]),
      spell_family: 9,
      family_flags_0: 1,
      duration_ms: -1,
      effects: [
        %Effect{
          type: :apply_aura,
          aura: :mod_increase_health_percent,
          misc_value: 0,
          base_points: -1,
          die_sides: 1,
          base_dice: 1
        }
      ]
    }

    pet = %Mob{
      object: %Object{guid: 2},
      unit: Stats.recompute(%Unit{level: 50, health: 1_000, base_health: 1_000, base_stamina: 0, auras: []}),
      internal: %Internal{pet: %Pet{owner_guid: 1}, spellbook: %{spell.id => spell}}
    }

    %{pet: PetTraining.restore_passives(pet, 0)}
  end

  defp modifier(amount) do
    %Holder{
      spell: %Spell{id: 10, spell_family: 9},
      auras: [%ThistleTea.Game.Aura{type: :add_flat_modifier, amount: amount, misc_value: 8, class_mask: 1}]
    }
  end
end
