defmodule ThistleTea.Game.Entity.Logic.SpellRemoval do
  @moduledoc "Removes known spells, their auras, and lost skills as one pure transition."

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Entity.Logic.CombatRatings
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Language
  alias ThistleTea.Game.Entity.Logic.PassiveSpells
  alias ThistleTea.Game.Entity.Logic.Proficiency
  alias ThistleTea.Game.Entity.Logic.Skills
  alias ThistleTea.Game.Entity.Logic.SpellSkills

  def remove(%Character{} = character, spell_ids, now) when is_list(spell_ids) and is_integer(now) do
    previous_skills = granted_skills(character)
    previous_ranks = SpellSkills.grants(character.internal.spellbook || %{})
    internal = character.internal
    spellbook = Map.drop(internal.spellbook || %{}, spell_ids)
    removed_ids = Enum.uniq(spell_ids ++ PassiveSpells.removed_ids(internal.spellbook, spellbook))

    character = %{
      character
      | internal: %{
          internal
          | spells: (internal.spells || []) -- spell_ids,
            spellbook: spellbook
        }
    }

    {character, aura_events} = AuraLogic.remove_spells(character, removed_ids, now)
    character = Effects.enqueue(character, aura_events)

    current_skills = granted_skills(character)
    current_ranks = SpellSkills.grants(character.internal.spellbook || %{})

    {skills, forgotten} =
      Skills.forget(
        character.player.skills || %{},
        previous_skills -- current_skills,
        character.internal.forgotten_skills
      )

    skills = SpellSkills.remove(skills, previous_ranks, current_ranks)
    forgotten = Map.drop(forgotten, Map.keys(previous_ranks) -- Map.keys(current_ranks))

    character = %{
      character
      | player: %{character.player | skills: skills},
        internal: %{character.internal | forgotten_skills: forgotten}
    }

    character
    |> CombatRatings.sync()
    |> Core.mark_broadcast_update()
  end

  defp granted_skills(character) do
    weapon_skills = character |> Proficiency.from_character() |> Proficiency.weapon_skills()
    weapon_skills ++ Language.skill_ids(character)
  end
end
