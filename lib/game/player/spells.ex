defmodule ThistleTea.Game.Player.Spells do
  @moduledoc """
  Boundary for teaching a player spells: applies rank supersession, rebuilds
  the spellbook, persists the character, and notifies the client of each
  learned or superseded spell.
  """
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.Proficiency
  alias ThistleTea.Game.Entity.Logic.SpellBook
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  def learn(%Character{internal: internal} = character, spell_ids) do
    existing_ids = internal.spells || []
    superseded_by = SpellLoader.superseded_by_map(existing_ids ++ spell_ids)

    case SpellBook.learn(existing_ids, spell_ids, superseded_by) do
      {_all_ids, []} ->
        :already_known

      {all_ids, events} ->
        spellbook = SpellLoader.build_spellbook(all_ids)
        character = %{character | internal: %{internal | spells: all_ids, spellbook: spellbook}}
        CharacterStore.put(character)
        Enum.each(events, &send_event_packet/1)
        send_proficiencies(character)
        {:ok, character, events}
    end
  end

  def send_proficiencies(%Character{internal: internal}) do
    prof = Proficiency.from_spellbook(internal.spellbook)

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
end
