defmodule ThistleTea.Game.Player.TalentsTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Talent, as: TalentData
  alias ThistleTea.Game.Player.Talents
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.World.Loader.Talent, as: TalentLoader

  setup do
    talent_id = System.unique_integer([:positive, :monotonic])
    spell_id = talent_id + 100_000
    dependent_spell_id = spell_id + 1
    talent = %TalentData{id: talent_id, tab_id: 1, tier: 0, rank_spell_ids: [spell_id]}
    previous_tabs = :ets.lookup(TalentLoader, {:tabs, 1})

    :ets.insert(TalentLoader, {{:talent, talent_id}, talent})
    :ets.insert(TalentLoader, {{:by_spell, spell_id}, {talent_id, 1, 0}})
    :ets.insert(TalentLoader, {{:dependent_spells, spell_id}, [dependent_spell_id]})
    :ets.insert(TalentLoader, {{:tabs, 1}, [1]})

    on_exit(fn ->
      :ets.delete(TalentLoader, {:talent, talent_id})
      :ets.delete(TalentLoader, {:by_spell, spell_id})
      :ets.delete(TalentLoader, {:dependent_spells, spell_id})

      case previous_tabs do
        [] -> :ets.delete(TalentLoader, {:tabs, 1})
        entries -> :ets.insert(TalentLoader, entries)
      end
    end)

    %{dependent_spell_id: dependent_spell_id, spell_id: spell_id, talent_id: talent_id}
  end

  describe "learn/3 and reset/1" do
    test "learns and resets talent-dependent abilities", context do
      state = state_without_spells()

      learned = Talents.learn(state, context.talent_id, 0)

      assert Enum.sort(learned.character.internal.spells) ==
               Enum.sort([context.spell_id, context.dependent_spell_id])

      reset = Talents.reset(learned)

      assert reset.character.internal.spells == []
      assert reset.character.internal.spellbook == %{}
    end
  end

  describe "reset_if_overbudget/2" do
    test "resets talents when the new level cannot support the spent points", %{spell_id: spell_id} do
      state = state_with_spell(spell_id, 9)

      state = Talents.reset_if_overbudget(state, 9)

      assert state.character.internal.spells == []
      assert state.character.internal.spellbook == %{}
      assert state.character.player.character_points1 == 0
    end

    test "keeps a valid talent allocation", %{spell_id: spell_id} do
      state = state_with_spell(spell_id, 10)

      assert Talents.reset_if_overbudget(state, 10) == state
    end
  end

  defp state_with_spell(spell_id, level) do
    id = System.unique_integer([:positive, :monotonic])

    character = %Character{
      id: id,
      object: %Object{guid: id},
      unit: %Unit{level: level, auras: []},
      player: %Player{character_points1: 0},
      internal: %Internal{spells: [spell_id], spellbook: %{spell_id => %Spell{id: spell_id}}}
    }

    %{character: character}
  end

  defp state_without_spells do
    id = System.unique_integer([:positive, :monotonic])

    character = %Character{
      id: id,
      object: %Object{guid: id},
      unit: %Unit{race: 1, class: 1, level: 10, auras: []},
      player: %Player{skills: %{}},
      internal: %Internal{spells: [], spellbook: %{}}
    }

    %{character: character}
  end
end
