defmodule ThistleTea.Game.Entity.Logic.PetTrainingTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Companion.EntityRef
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Data.PetAbility
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.PetProgression
  alias ThistleTea.Game.Entity.Logic.PetTraining
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Entity.Logic.Stats
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect

  setup [:build_pet]

  describe "learn/6" do
    test "charges only the upgrade difference and replaces autocast and action slots", context do
      %{pet: pet, abilities: abilities} = context
      first = abilities[100].spell
      control = %{pet.internal.pet | autocast: MapSet.new([100]), action_bar: %{5 => {100, 0xC1}}}
      pet = %{pet | internal: %{pet.internal | spellbook: %{100 => first}, pet: control}}

      assert {:ok, trained} = PetTraining.learn(pet, 1, teaching(101), abilities, 208, 0)
      assert Map.keys(trained.internal.spellbook) == [101]
      assert trained.internal.pet.training_points == 15
      assert trained.unit.training_points == -16
      assert trained.internal.pet.autocast == MapSet.new([101])
      assert trained.internal.pet.action_bar[5] == {101, 0xC1}
      assert elem(trained.internal.pet.action_bar[3], 0) == 0
      assert Enum.map(trained.internal.creature.spells, & &1.spell_id) == [101]
      assert %{spells: [101], training_points: 15} = PetProgression.snapshot(trained)
      assert {:error, :spell_learned} = PetTraining.learn(trained, 1, teaching(101), abilities, 208, 1)
      assert {:error, :spell_learned} = PetTraining.learn(trained, 1, teaching(100), abilities, 208, 1)
    end

    test "credits ranks in restored spellbooks without rank metadata", %{pet: pet, abilities: abilities} do
      pet = %{pet | internal: %{pet.internal | spellbook: %{100 => %Spell{id: 100}}}}
      assert {:ok, trained} = PetTraining.learn(pet, 1, teaching(101), abilities, 208, 0)
      assert trained.internal.pet.training_points == 15
      assert Map.keys(trained.internal.spellbook) == [101]
    end

    test "applies passive stats immediately and replaces rather than stacks ranks", %{pet: pet, abilities: abilities} do
      assert {:ok, first} = PetTraining.learn(pet, 1, teaching(200), abilities, 208, 0)
      assert first.unit.stamina == pet.unit.stamina + 5
      assert first.unit.max_health == pet.unit.max_health + 50
      assert first.internal.creature.spells == []
      assert {:ok, second} = PetTraining.learn(first, 1, teaching(201), abilities, 208, 1)
      assert second.unit.stamina == pet.unit.stamina + 10
      assert second.unit.max_health == pet.unit.max_health + 100
      assert Enum.map(second.unit.auras, & &1.spell.id) == [201]
      assert second.internal.pet.training_points == 10
      assert PetProgression.snapshot(second).spells == [201]

      restored = %{pet | internal: %{pet.internal | spellbook: second.internal.spellbook}}
      restored = PetTraining.restore_passives(restored, 100)
      assert restored.unit.stamina == second.unit.stamina
      assert restored.unit.max_health == second.unit.max_health
      assert PetTraining.restore_passives(restored, 101).unit.max_health == second.unit.max_health
    end

    test "permits zero-cost training while in training debt", %{pet: pet, abilities: abilities} do
      pet = %{pet | internal: %{pet.internal | pet: %{pet.internal.pet | training_points: -10}}}
      assert {:ok, trained} = PetTraining.learn(pet, 1, teaching(300), abilities, 208, 0)
      assert trained.internal.pet.training_points == -10
      assert trained.unit.training_points == 10
      assert {:error, :training_points} = PetTraining.learn(pet, 1, teaching(100), abilities, 208, 0)
    end
  end

  describe "validate/5" do
    test "rejects ownership, non-hunter pets, broken bonds, and corpses", %{pet: pet, abilities: abilities} do
      assert {:error, :no_pet} = PetTraining.validate(pet, 9, teaching(100), abilities, 208)

      for control <- [%{pet.internal.pet | kind: :summon}, %{pet.internal.pet | broken?: true}] do
        invalid = %{pet | internal: %{pet.internal | pet: control}}
        assert {:error, :no_pet} = PetTraining.validate(invalid, 1, teaching(100), abilities, 208)
      end

      dead = %{pet | unit: %{pet.unit | health: 0}}
      assert {:error, :targets_dead} = PetTraining.validate(dead, 1, teaching(100), abilities, 208)
    end

    test "checks family, pet level, available points, and unknown abilities", %{pet: pet, abilities: abilities} do
      assert {:error, :bad_targets} = PetTraining.validate(pet, 1, teaching(100), abilities, 209)
      assert :ok = PetTraining.validate(pet, 1, teaching(200), abilities, 209)
      assert {:error, :lowlevel} = PetTraining.validate(pet, 1, %{teaching(100) | spell_level: 21}, abilities, 208)
      assert {:error, :not_known} = PetTraining.validate(pet, 1, teaching(999), abilities, 208)
      poor = %{pet | internal: %{pet.internal | pet: %{pet.internal.pet | training_points: 4}}}
      assert {:error, :training_points} = PetTraining.validate(poor, 1, teaching(100), abilities, 208)
    end

    test "limits active families to four while allowing upgrades and passives", %{pet: pet, abilities: abilities} do
      book = Map.new([100, 300, 400, 500], &{&1, %Spell{id: &1}})
      pet = %{pet | internal: %{pet.internal | spellbook: book}}
      abilities = Map.put(abilities, 600, ability(600, 600, 1, 1, [270]))
      assert {:error, :too_many_skills} = PetTraining.validate(pet, 1, teaching(600), abilities, 208)
      assert :ok = PetTraining.validate(pet, 1, teaching(101), abilities, 208)
      assert :ok = PetTraining.validate(pet, 1, teaching(200), abilities, 208)
    end
  end

  describe "SpellEffect.receive/4" do
    test "queues one owner-local purchase with the current pet identity", %{pet: pet} do
      owner = %Character{object: %Object{guid: 1}, unit: %Unit{health: 100}, internal: %Internal{}}
      owner = Companion.activate(owner, :hunter_pet, %EntityRef{guid: 2, entry: 1, spell_id: 1515})

      for type <- [:learn_spell, :learn_pet_spell] do
        spell = %{teaching(100) | effects: [%Effect{type: type, implicit_target_a: :pet, trigger_spell_id: 100}]}
        context = %CastContext{caster_guid: 1, caster_level: 20, target_role: :caster}
        {_, effects} = SpellEffect.receive(owner, context, spell, 0)

        assert [%Effects.LearnPetSpell{target_guid: 2, spell: ^spell}] =
                 Enum.filter(effects, &is_struct(&1, Effects.LearnPetSpell))

        {_, effects} = SpellEffect.receive(pet, %{context | target_role: :pet}, spell, 0)
        refute Enum.any?(effects, &is_struct(&1, Effects.LearnPetSpell))
      end
    end
  end

  defp teaching(id),
    do: %Spell{id: id + 1_000, effects: [%Effect{type: :learn_spell, implicit_target_a: :pet, trigger_spell_id: id}]}

  defp ability(id, first, rank, cost, skills) do
    %PetAbility{spell: %Spell{id: id, first_in_chain: first, rank: rank}, cost: cost, skills: skills}
  end

  defp passive(id, rank, amount) do
    ability = ability(id, 200, rank, amount, [270])

    spell = %{
      ability.spell
      | attributes: MapSet.new([:passive]),
        duration_ms: -1,
        effects: [
          %Effect{
            type: :apply_aura,
            aura: :mod_stat,
            base_points: amount,
            misc_value: 2,
            implicit_target_a: :caster
          }
        ]
    }

    %{ability | spell: spell}
  end

  defp build_pet(_context) do
    pet = %Mob{
      object: %Object{guid: 2},
      unit:
        Stats.recompute(%Unit{health: 100, level: 20, base_stamina: 30, base_health: 100, pet_loyalty: 2, auras: []}),
      internal: %Internal{
        pet: %Pet{kind: :hunter, owner_guid: 1, training_points: 20},
        creature: %Creature{},
        spellbook: %{}
      }
    }

    abilities = [
      ability(100, 100, 1, 5, [208]),
      ability(101, 100, 2, 10, [208]),
      passive(200, 1, 5),
      passive(201, 2, 10),
      ability(300, 300, 1, 0, [270])
    ]

    %{pet: pet, abilities: Map.new(abilities, &{&1.spell.id, &1})}
  end
end
