defmodule ThistleTea.Game.Player.Characters do
  @moduledoc """
  Character creation flow: validates name uniqueness and the per-account
  limit, assigns the guid and starting equipment, and stores the new
  character.
  """
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader

  @character_limit 10

  def create(%Character{} = character) do
    with {:exists, nil} <- {:exists, CharacterStore.get_by_name(character.internal.name)},
         {:limit, false} <- {:limit, at_character_limit?(character.account_id)} do
      character =
        character
        |> CharacterStore.create()
        |> generate_and_assign_equipment()
        |> Character.restore_health_and_mana()
        |> CharacterStore.put()

      {:ok, character}
    else
      {:exists, %Character{}} -> {:error, :character_exists}
      {:limit, true} -> {:error, :character_limit}
    end
  end

  def generate_and_assign_equipment(%Character{object: %{guid: owner_guid}, unit: %Unit{} = unit} = character)
      when is_integer(owner_guid) and owner_guid > 0 do
    player =
      ItemLoader.random_equipment(unit.race, unit.class, unit.level)
      |> Enum.reduce(character.player, fn {slot, template}, player ->
        case template && ItemStore.create(template, owner: owner_guid) do
          %Item{} = item -> Inventory.equip(player, slot, item)
          _ -> player
        end
      end)

    Character.sync_equipment_stats(%{character | player: player})
  end

  defp at_character_limit?(account_id) do
    length(CharacterStore.for_account(account_id)) >= @character_limit
  end
end
