defmodule ThistleTea.Game.Player.TalentsTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Companion.EntityRef
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Talent, as: TalentData
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Player.Talents
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.SpellPetAura
  alias ThistleTea.Game.World.Loader.Talent, as: TalentLoader
  alias ThistleTea.Game.WorldRef

  @moduletag :dbc_db

  @spirit_bond_rank_one_aura 19_579
  @spirit_bond_rank_two_aura 24_529

  setup do
    talent_id = System.unique_integer([:positive, :monotonic])
    spell_id = talent_id + 100_000
    rank_two_spell_id = spell_id + 1
    dependent_spell_id = rank_two_spell_id + 1
    talent = %TalentData{id: talent_id, tab_id: 1, tier: 0, rank_spell_ids: [spell_id, rank_two_spell_id]}
    previous_tabs = :ets.lookup(TalentLoader, {:tabs, 1})

    :ets.insert(TalentLoader, {{:talent, talent_id}, talent})
    :ets.insert(TalentLoader, {{:by_spell, spell_id}, {talent_id, 1, 0}})
    :ets.insert(TalentLoader, {{:by_spell, rank_two_spell_id}, {talent_id, 1, 1}})
    :ets.insert(TalentLoader, {{:superseded_by, spell_id}, rank_two_spell_id})
    :ets.insert(TalentLoader, {{:dependent_spells, spell_id}, [dependent_spell_id]})
    :ets.insert(TalentLoader, {{:tabs, 1}, [1]})
    :ets.insert(SpellPetAura, {spell_id, [{0, @spirit_bond_rank_one_aura}]})
    :ets.insert(SpellPetAura, {rank_two_spell_id, [{0, @spirit_bond_rank_two_aura}]})

    on_exit(fn ->
      :ets.delete(TalentLoader, {:talent, talent_id})
      :ets.delete(TalentLoader, {:by_spell, spell_id})
      :ets.delete(TalentLoader, {:by_spell, rank_two_spell_id})
      :ets.delete(TalentLoader, {:superseded_by, spell_id})
      :ets.delete(TalentLoader, {:dependent_spells, spell_id})
      :ets.delete(SpellPetAura, spell_id)
      :ets.delete(SpellPetAura, rank_two_spell_id)

      case previous_tabs do
        [] -> :ets.delete(TalentLoader, {:tabs, 1})
        entries -> :ets.insert(TalentLoader, entries)
      end
    end)

    %{
      dependent_spell_id: dependent_spell_id,
      rank_two_spell_id: rank_two_spell_id,
      spell_id: spell_id,
      talent_id: talent_id
    }
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

    test "replaces a superseded talent's pet aura link", context do
      pet_guid = Guid.from_low_guid(:pet, 1, System.unique_integer([:positive, :monotonic]))
      {:ok, _owner} = Entity.register(pet_guid)
      on_exit(fn -> Entity.unregister(pet_guid) end)

      rank_one_aura = SpellLoader.load(@spirit_bond_rank_one_aura)

      state =
        context.spell_id
        |> state_with_spell(11)
        |> with_pet(pet_guid)
        |> then(fn state ->
          {character, _events} =
            AuraLogic.apply_spell(state.character, pet_guid, state.character.unit.level, rank_one_aura, 1_000)

          %{state | character: character}
        end)

      learned = Talents.learn(state, context.talent_id, 1)

      refute context.spell_id in learned.character.internal.spells
      assert context.rank_two_spell_id in learned.character.internal.spells
      refute AuraLogic.has_spell?(learned.character, @spirit_bond_rank_one_aura)

      assert_receive {:"$gen_cast", {:remove_aura, @spirit_bond_rank_one_aura, ^pet_guid}}

      assert_receive {:"$gen_cast",
                      {:receive_spell, %CastContext{caster_guid: ^pet_guid, target_guid: ^pet_guid},
                       %Spell{id: @spirit_bond_rank_two_aura}}}
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
      unit: %Unit{race: 1, class: 1, level: level, auras: []},
      player: %Player{character_points1: 0, skills: %{}},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{
        spells: [spell_id],
        spellbook: %{spell_id => %Spell{id: spell_id}},
        world: %WorldRef{map_id: 0}
      }
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

  defp with_pet(%{character: character} = state, pet_guid) do
    entity_ref = %EntityRef{guid: pet_guid, entry: 1, spell_id: 1515}
    %{state | character: Companion.activate(character, :hunter_pet, entity_ref)}
  end
end
