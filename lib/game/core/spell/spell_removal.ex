defmodule ThistleTea.Game.Core.Spell.SpellRemoval do
  @moduledoc "Removes known spells, their auras, and lost skills as one pure transition."

  alias ThistleTea.Game.Core.Aura, as: AuraCore
  alias ThistleTea.Game.Core.Chat.Language
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Item.Proficiency
  alias ThistleTea.Game.Core.Skills
  alias ThistleTea.Game.Core.Skills.SpellSkills
  alias ThistleTea.Game.Core.Spell.PassiveSpells
  alias ThistleTea.Game.Core.Stats.CombatRatings

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

    {character, aura_events} = AuraCore.remove_spells(character, removed_ids, now)
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
    |> Entity.mark_broadcast_update()
  end

  defp granted_skills(character) do
    weapon_skills = character |> Proficiency.from_character() |> Proficiency.weapon_skills()
    weapon_skills ++ Language.skill_ids(character)
  end
end
