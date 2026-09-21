defmodule ThistleTea.Game.Entity.Logic.SpellRemoval do
  @moduledoc "Removes known spells, their auras, and lost weapon and language skills as one pure transition."

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Entity.Logic.CombatRatings
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Language
  alias ThistleTea.Game.Entity.Logic.Proficiency
  alias ThistleTea.Game.Entity.Logic.Skills

  def remove(%Character{} = character, spell_ids, now) when is_list(spell_ids) and is_integer(now) do
    previous_skills = granted_skills(character)
    {character, aura_events} = AuraLogic.remove_spells(character, spell_ids, now)
    character = Effects.enqueue(character, aura_events)
    internal = character.internal

    character = %{
      character
      | internal: %{
          internal
          | spells: (internal.spells || []) -- spell_ids,
            spellbook: Map.drop(internal.spellbook || %{}, spell_ids)
        }
    }

    current_skills = granted_skills(character)

    {skills, forgotten} =
      Skills.forget(
        character.player.skills || %{},
        previous_skills -- current_skills,
        character.internal.forgotten_skills
      )

    character = %{
      character
      | player: %{character.player | skills: skills},
        internal: %{character.internal | forgotten_skills: forgotten}
    }

    CombatRatings.sync(character)
  end

  defp granted_skills(character) do
    weapon_skills = character |> Proficiency.from_character() |> Proficiency.weapon_skills()
    weapon_skills ++ Language.skill_ids(character)
  end
end
