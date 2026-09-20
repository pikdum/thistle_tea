defmodule ThistleTea.Game.Entity.Logic.PetLearningTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.EffectResolver.PetLearning, as: LearningResolver
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.PetLearning
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Target

  setup [:build_pet]

  describe "used/2" do
    test "only a living, owned hunter pet can request discovery", %{pet: pet, spell: spell} do
      assert {%Mob{}, [%Effects.PetAbilityUsed{spell_id: 100}]} = pet |> PetLearning.used(spell) |> Effects.drain()

      for control <- [
            nil,
            %Pet{kind: :summon},
            %Pet{kind: :hunter, broken?: true},
            %Pet{kind: :hunter, possessed?: true}
          ] do
        entity = %{pet | internal: %{pet.internal | pet: control}}
        assert PetLearning.used(entity, spell) == entity
      end

      dead = %{pet | unit: %{pet.unit | health: 0}}
      assert PetLearning.used(dead, spell) == dead
      assert PetLearning.used(pet, %Spell{id: 999}) == pet
      assert PetLearning.used(pet, %{spell | attributes: MapSet.new([:passive])}) == pet
    end
  end

  describe "cast launch" do
    test "requests once after launch and never for a canceled cast", %{pet: pet, spell: spell} do
      casting = Casting.start(pet, %{spell | cast_time_ms: 500}, Target.none(), 1_000)
      assert {:waiting, waiting, 500} = Casting.advance(casting, 1_000)
      refute Enum.any?(waiting.internal.events || [], &is_struct(&1, Effects.PetAbilityUsed))
      canceled = Casting.cancel(waiting)
      assert {:idle, ^canceled} = Casting.advance(canceled, 2_000)
      refute Enum.any?(canceled.internal.events, &is_struct(&1, Effects.PetAbilityUsed))

      assert {:finished, launched} = Casting.advance(casting, 1_500)
      assert Enum.count(launched.internal.events, &is_struct(&1, Effects.PetAbilityUsed)) == 1
      assert {:idle, ^launched} = Casting.advance(launched, 2_000)
    end
  end

  describe "resolve/3" do
    test "uses the reference ten winning outcomes out of 101", %{pet: pet} do
      effect = %Effects.PetAbilityUsed{spell_id: 100}
      profile = %{recipes: %{100 => 300}}

      for roll <- [0, 9] do
        assert [%Effects.LearnPetRecipe{source_guid: source, target_guid: 7, spell_id: 300}] =
                 LearningResolver.resolve(pet, effect, profile: profile, roll: fn -> roll end)

        assert source == pet.object.guid
      end

      for roll <- [10, 100] do
        assert LearningResolver.resolve(pet, effect, profile: profile, roll: fn -> roll end) == []
      end

      assert LearningResolver.resolve(pet, %{effect | spell_id: 101},
               profile: profile,
               roll: fn -> flunk("unknown ability rolled") end
             ) == []
    end
  end

  defp build_pet(_context) do
    spell = %Spell{id: 100, power_type: 2, mana_cost: 0}

    pet = %Mob{
      object: %Object{guid: Guid.runtime(:pet, 2960)},
      unit: %Unit{health: 100, level: 10, power3: 100},
      internal: %Internal{pet: %Pet{kind: :hunter, owner_guid: 7}, spellbook: %{100 => spell}}
    }

    %{pet: pet, spell: spell}
  end
end
