defmodule ThistleTea.Game.Entity.Logic.EquipmentTransitions do
  @moduledoc """
  Validates client equipment changes and starts cooldowns for newly occupied
  equipment slots. Inventory commits supply item and spell lookups explicitly.
  """
  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cooldowns

  def validate(%Character{internal: %{in_combat: true}} = character, %Player{} = player, get_item, now) do
    character.player
    |> changes(player)
    |> Enum.reduce_while(:ok, fn {old_guid, new_guid}, :ok ->
      case validate_combat_change(character, get_item.(old_guid), get_item.(new_guid), now) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason, new_guid || 0, old_guid || 0}}
      end
    end)
  end

  def validate(%Character{}, %Player{}, _get_item, _now), do: :ok

  def apply(%Character{} = character, %Player{} = previous, get_item, get_spell, now) do
    previous
    |> changes(character.player)
    |> Enum.reduce(character, fn {_old_guid, new_guid}, character ->
      case get_item.(new_guid) do
        %Item{} = item ->
          character
          |> equip_cooldowns(item, get_spell, now)
          |> weapon_cooldown(Item.template(item), get_spell, now)

        _missing ->
          character
      end
    end)
  end

  defp changes(%Player{} = previous, %Player{} = player) do
    old = Map.from_struct(previous)
    new = Map.from_struct(player)

    for slot <- Inventory.slots(), old[slot] != new[slot], do: {old[slot], new[slot]}
  end

  defp validate_combat_change(character, old_item, new_item, now) do
    cond do
      not changeable_in_combat?(old_item) or not changeable_in_combat?(new_item) -> {:error, :not_in_combat}
      weapon?(new_item) and Cooldowns.weapon_change_locked?(character, now) -> {:error, :cant_do_right_now}
      true -> :ok
    end
  end

  defp changeable_in_combat?(%Item{} = item) do
    template = Item.template(item)
    template.class in [2, 6] or template.inventory_type in [14, 23, 28]
  end

  defp changeable_in_combat?(_missing), do: true

  defp weapon?(%Item{} = item), do: Item.template(item).class == 2
  defp weapon?(_missing), do: false

  defp equip_cooldowns(character, %Item{} = item, get_spell, now) do
    item
    |> Item.template()
    |> equip_spell_ids()
    |> Enum.reduce(character, fn id, character ->
      case get_spell.(id) do
        %Spell{} = spell -> Cooldowns.equip(character, spell, item.object.guid, now)
        _missing -> character
      end
    end)
  end

  defp equip_spell_ids(%ItemTemplate{flags: flags}) when (flags &&& 0x80) != 0, do: []

  defp equip_spell_ids(%ItemTemplate{} = template) do
    [
      {template.spellid_1, template.spelltrigger_1},
      {template.spellid_2, template.spelltrigger_2},
      {template.spellid_3, template.spelltrigger_3},
      {template.spellid_4, template.spelltrigger_4},
      {template.spellid_5, template.spelltrigger_5}
    ]
    |> Enum.flat_map(fn
      {id, 0} when is_integer(id) and id > 0 -> [id]
      _other -> []
    end)
  end

  defp weapon_cooldown(%Character{internal: %{in_combat: true}} = character, template, get_spell, now) do
    if not Core.dead?(character) and (template.class == 2 or template.inventory_type == 28) do
      spell_id = if character.unit.class == 4, do: 6123, else: 6119

      case get_spell.(spell_id) do
        %Spell{} = spell -> Cooldowns.start_weapon_change(character, spell, now)
        _missing -> character
      end
    else
      character
    end
  end

  defp weapon_cooldown(character, _template, _get_spell, _now), do: character
end
