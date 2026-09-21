defmodule ThistleTea.Game.Entity.Logic.OpenLockTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Lock
  alias ThistleTea.Game.Entity.Data.Lock.Requirement
  alias ThistleTea.Game.Entity.Logic.OpenLock
  alias ThistleTea.Game.Entity.Logic.Skills
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  describe "resolve/4" do
    test "requires a matching lock type and sufficient skill" do
      character = character(186, 64)
      lock = lock(3, 65)
      assert OpenLock.resolve(character, spell(3), lock) == {:error, :low_castlevel}

      assert OpenLock.resolve(character(186, 65), spell(3), lock) ==
               {:ok, %OpenLock{lock_id: 39, lock_type: 3, skill_id: 186, value: 65, required: 65, gain?: true}}

      assert OpenLock.resolve(character, spell(2), lock) == {:error, :bad_targets}
      assert OpenLock.resolve(character, spell(5), lock) == {:error, :bad_targets}
      assert OpenLock.resolve(character, spell(3), %Lock{id: 85}) == {:error, :bad_targets}
    end

    test "uses skill bonuses only for known skills" do
      aura = %Holder{
        spell: %Spell{id: 1},
        auras: [%Aura{type: :mod_skill, misc_value: 186, amount: 5}]
      }

      character = character(186, 60)
      character = %{character | unit: %{character.unit | auras: [aura]}}
      assert {:ok, %OpenLock{value: 65}} = OpenLock.resolve(character, spell(3), lock(3, 65))
      character = %{character | player: %{character.player | skills: %{}}}
      assert {:error, :low_castlevel} = OpenLock.resolve(character, spell(3), lock(3, 1))
    end

    test "casting items use their own strength without profession bonuses or gains" do
      character = character(633, 300)
      key_spell = spell(1, 124)
      assert {:ok, %OpenLock{value: 125, gain?: false}} = OpenLock.resolve(character, key_spell, lock(1, 125), 15_870)
      assert {:error, :low_castlevel} = OpenLock.resolve(character, key_spell, lock(1, 150), 15_870)

      assert {:ok, %OpenLock{value: 150, gain?: false}} =
               OpenLock.resolve(character, spell(16, 149), lock(16, 150), 4367)
    end

    test "recognizes exact item keys and the first matching skill alternative" do
      lock = %Lock{
        id: 39,
        requirements: [%Requirement{type: :item, index: 123}, %Requirement{type: :skill, index: 1, skill: 100}]
      }

      assert {:ok, %OpenLock{skill_id: nil}} = OpenLock.resolve(character(633, 1), spell(1), lock, 123)
      assert {:error, :low_castlevel} = OpenLock.resolve(character(633, 1), spell(1), lock, 456)
      assert {:ok, %OpenLock{skill_id: nil}} = OpenLock.key(lock, fn 123 -> 1 end)
      assert {:error, :bad_targets} = OpenLock.key(lock, fn _ -> 0 end)
    end

    test "ordinary opening has no profession requirement or gain" do
      assert {:ok, %OpenLock{skill_id: nil, gain?: false}} = OpenLock.resolve(character(186, 1), spell(5), lock(5, 100))
    end
  end

  defp character(skill, value) do
    skills = Skills.learn_rank(%{}, skill, 300)
    skills = Map.update!(skills, skill, &%{&1 | value: value})
    %Character{player: %Player{skills: skills}, unit: %Unit{auras: []}}
  end

  defp spell(type, points \\ -1),
    do: %Spell{id: 2575, effects: [%Effect{type: :open_lock, misc_value: type, base_points: points}]}

  defp lock(type, required), do: %Lock{id: 39, requirements: [%Requirement{type: :skill, index: type, skill: required}]}
end
