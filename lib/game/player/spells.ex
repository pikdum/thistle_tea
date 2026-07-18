defmodule ThistleTea.Game.Player.Spells do
  @moduledoc """
  Boundary for teaching a player spells: applies rank supersession, rebuilds
  the spellbook, persists the character, and notifies the client of each
  learned or superseded spell.
  """
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Entity.Logic.Proficiency
  alias ThistleTea.Game.Entity.Logic.SpellBook
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Loader.Skill, as: SkillLoader
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  def learn(%Character{internal: internal} = character, spell_ids) do
    existing_ids = internal.spells || []
    superseded_by = SpellLoader.superseded_by_map(existing_ids ++ spell_ids)

    case SpellBook.learn(existing_ids, spell_ids, superseded_by) do
      {_all_ids, []} ->
        :already_known

      {all_ids, events} ->
        spellbook = SpellLoader.build_spellbook(all_ids)

        character =
          %{character | internal: %{internal | spells: all_ids, spellbook: spellbook}}
          |> learn_skills()

        CharacterStore.put(character)
        Enum.each(events, &send_event_packet/1)
        send_proficiencies(character)
        {:ok, character, events}
    end
  end

  defp learn_skills(%Character{unit: unit, player: player, internal: internal} = character) do
    new_skills = SkillLoader.initial_skills(internal.spells, unit.race, unit.class, unit.level)
    skills = Map.merge(new_skills, player.skills || %{})
    %{character | player: %{player | skills: skills}}
  end

  def unlearn(%Character{} = character, spell_ids, now) when is_list(spell_ids) and is_integer(now) do
    {character, aura_events} = AuraLogic.remove_spells(character, spell_ids, now)
    character = Event.enqueue(character, aura_events)
    internal = character.internal

    character = %{
      character
      | internal: %{
          internal
          | spells: (internal.spells || []) -- spell_ids,
            spellbook: Map.drop(internal.spellbook || %{}, spell_ids)
        }
    }

    CharacterStore.put(character)
    Enum.each(spell_ids, &Network.send_packet(%Message.SmsgRemovedSpell{spell_id: &1}))
    character
  end

  def apply_passives(%Character{internal: %{spellbook: spellbook}} = character, now)
      when is_map(spellbook) and is_integer(now) do
    spellbook
    |> Map.values()
    |> Enum.filter(&passive_aura_spell?/1)
    |> Enum.reduce(character, fn spell, character ->
      if AuraLogic.has_spell?(character, spell.id) do
        character
      else
        {character, events} =
          AuraLogic.apply_spell(character, character.object.guid, character.unit.level || 1, spell, now)

        Event.enqueue(character, events)
      end
    end)
  end

  def apply_passives(character, _now), do: character

  defp passive_aura_spell?(%Spell{} = spell) do
    Spell.attribute?(spell, :passive) and (spell.stances || 0) == 0 and Spell.aura_effects(spell) != []
  end

  def send_proficiencies(%Character{} = character) do
    prof = Proficiency.from_character(character)

    Network.send_packet(%Message.SmsgSetProficiency{
      item_class: Proficiency.item_class_weapon(),
      subclass_mask: prof.weapon_mask
    })

    Network.send_packet(%Message.SmsgSetProficiency{
      item_class: Proficiency.item_class_armor(),
      subclass_mask: prof.armor_mask
    })
  end

  defp send_event_packet({:learned, spell_id}) do
    Network.send_packet(%Message.SmsgLearnedSpell{spell_id: spell_id})
  end

  defp send_event_packet({:superseded, old_id, new_id}) do
    Network.send_packet(%Message.SmsgSupercededSpell{old_spell_id: old_id, new_spell_id: new_id})
  end

  defp send_event_packet({:removed, spell_id}) do
    Network.send_packet(%Message.SmsgRemovedSpell{spell_id: spell_id})
  end
end
