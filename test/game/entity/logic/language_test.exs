defmodule ThistleTea.Game.Entity.Logic.LanguageTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Language
  alias ThistleTea.Game.Entity.Logic.Skills
  alias ThistleTea.Game.Entity.Logic.SpellRemoval
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  setup [:speaker]

  describe "known?/2" do
    test "derives languages from learned effects", %{character: character} do
      assert Language.known?(character, 7)
      refute Language.known?(character, 6)
      refute Language.known?(character, 0)
      refute Language.known?(character, 0xFFFFFFFF)

      dwarven = %Spell{id: 672, effects: [%Effect{type: :language, misc_value: 6}]}
      internal = %{character.internal | spellbook: Map.put(character.internal.spellbook, 672, dwarven)}
      skills = Map.put(character.player.skills, 111, Skills.new_entry(:language, false, 50))
      character = %{character | internal: internal, player: %{character.player | skills: skills}}
      assert Language.known?(character, 6)
      assert Enum.sort(Language.skill_ids(character)) == [98, 111]

      character = SpellRemoval.remove(character, [672], 1_000)
      refute Language.known?(character, 6)
      refute Map.has_key?(character.player.skills, 111)
      assert character.player.skills[98].value == 300
      assert Language.known?(character, 7)
    end
  end

  describe "resolve/3" do
    test "rejects unlearned languages and forged universal speech", %{character: character} do
      assert Language.resolve(character, 0, 7) == {:ok, 7}
      assert Language.resolve(character, 0, 6) == {:error, :not_learned}

      for type <- [0, 1, 2, 3, 4, 5, 6, 8, 0x0E, 0x57, 0x58] do
        assert Language.resolve(character, type, 0) == {:error, :invalid_language}
      end

      assert Language.resolve(character, 0, 99) == {:error, :invalid_language}
      assert Language.resolve(character, 0x0A, 7) == {:error, :invalid_language}
    end

    test "preserves addon traffic only in supported audiences", %{character: character} do
      {character, _events} = Aura.apply_spell(character, 2, 50, curse(), 1_000)

      for type <- [1, 2, 3, 4, 0x0E, 0x57, 0x58] do
        assert Language.resolve(character, type, Language.addon()) == {:ok, Language.addon()}
      end

      for type <- [0, 5, 6, 8, 0x14, 0x15] do
        assert Language.resolve(character, type, Language.addon()) == {:error, :invalid_language}
      end
    end

    test "keeps whispers, emotes and availability text universal", %{character: character} do
      {character, _events} = Aura.apply_spell(character, 2, 50, curse(), 1_000)

      for type <- [6, 8, 0x14, 0x15] do
        assert Language.resolve(character, type, 7) == {:ok, 0}
      end

      for type <- [0x14, 0x15], do: assert(Language.resolve(character, type, 0) == {:ok, 0})
    end

    test "applies curses without teaching the forced language", %{character: character} do
      {character, _events} = Aura.apply_spell(character, 2, 50, curse(), 1_000)

      for type <- [0, 1, 2, 5, 0x0E, 0x57, 0x58] do
        assert Language.resolve(character, type, 7) == {:ok, 8}
      end

      refute Language.known?(character, 8)
      assert Language.resolve(character, 0, 8) == {:error, :not_learned}
    end

    test "restores speech on curse removal, expiry and death", %{character: character} do
      {cursed, _events} = Aura.apply_spell(character, 2, 50, curse(), 1_000)
      assert Language.resolve(cursed, 0, 7) == {:ok, 8}
      {dispelled, _events} = Aura.dispel(cursed, 2, 2_000, :negative)
      {expired, _events} = Aura.expire_due(cursed, 31_000)
      dead = Core.take_damage(cursed, 100, 2_000, environmental: true)

      for cleared <- [dispelled, expired, dead] do
        assert Language.resolve(cleared, 0, 7) == {:ok, 7}
      end
    end

    test "remaining overrides resume when the first source ends", %{character: character} do
      {character, _events} = Aura.apply_spell(character, 2, 50, curse(), 1_000)

      draconic = %{
        curse()
        | id: 23_758,
          effects: [%Effect{index: 0, type: :apply_aura, aura: :mod_language, misc_value: 11}]
      }

      {character, _events} = Aura.apply_spell(character, 3, 50, draconic, 2_000)
      assert Language.resolve(character, 0, 7) == {:ok, 8}

      {character, _events} = Aura.remove_source_spell(character, 1714, 2, 3_000)
      assert Language.resolve(character, 0, 7) == {:ok, 11}
      {character, _events} = Aura.expire_due(character, 32_000)
      assert Language.resolve(character, 0, 7) == {:ok, 7}
    end
  end

  defp speaker(_context) do
    common = %Spell{id: 668, effects: [%Effect{type: :language, misc_value: 7}]}

    %{
      character: %Character{
        object: %Object{guid: 1},
        unit: %Unit{health: 100, max_health: 100, level: 50, auras: []},
        player: %Player{skills: %{98 => Skills.new_entry(:language, false, 50)}},
        internal: %Internal{spells: [668], spellbook: %{668 => common}},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }
    }
  end

  defp curse do
    %Spell{
      id: 1714,
      duration_ms: 30_000,
      dispel_type: 2,
      attributes: MapSet.new([:negative]),
      effects: [%Effect{index: 0, type: :apply_aura, aura: :mod_language, misc_value: 8}]
    }
  end
end
