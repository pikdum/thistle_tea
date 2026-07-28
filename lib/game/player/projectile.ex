defmodule ThistleTea.Game.Player.Projectile do
  @moduledoc """
  Resolves ranged cast projectile fields from a player's selected ammunition.
  """

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Spell
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

  def fields(%Character{player: %Player{ammo_id: ammo_id, visible_item_18_0: weapon_id}}, %Spell{} = spell) do
    if Spell.ranged_ability?(spell) do
      projectile_fields(weapon_id, ammo_id)
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
