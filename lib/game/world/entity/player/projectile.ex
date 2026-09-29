defmodule ThistleTea.Game.World.Entity.Player.Projectile do
  @moduledoc """
  Resolves ranged cast projectile fields from a player's selected ammunition.
  """

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.ItemTemplate
  alias ThistleTea.Game.Core.Inventory
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader

  @cast_flag_ammo 0x20

  def fields(%Character{} = character, spell_id) when is_integer(spell_id) do
    case character do
      %Character{internal: %Internal{spellbook: spellbook}} when is_map(spellbook) ->
        fields(character, Map.get(spellbook, spell_id))

      %Character{} ->
        none()
    end
  end

  def fields(%Character{player: %Player{ammo_id: ammo_id} = player}, %Spell{} = spell) do
    if Spell.ranged_ability?(spell) do
      projectile_fields(Inventory.equipment_entry(player, :ranged), ammo_id)
    else
      none()
    end
  end

  def fields(_entity, _spell), do: none()

  defp projectile_fields(weapon_id, ammo_id) do
    case ItemLoader.get_cached_template(weapon_id) do
      %ItemTemplate{inventory_type: 25} = thrown -> present(thrown)
      %ItemTemplate{} -> ammo_id |> ItemLoader.get_cached_template() |> present()
      _missing_weapon -> present(nil)
    end
  end

  defp present(%ItemTemplate{} = item) do
    %{flags: @cast_flag_ammo, display_id: item.display_id, inventory_type: item.inventory_type}
  end

  defp present(_item), do: %{flags: @cast_flag_ammo, display_id: 0, inventory_type: 0}
  defp none, do: %{flags: 0, display_id: nil, inventory_type: nil}
end
