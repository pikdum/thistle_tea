defmodule ThistleTea.Game.Entity.Logic.Ammunition do
  @moduledoc """
  Pure ammunition eligibility and inventory costs for ranged attacks.
  """

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Logic.Durability
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Inventory.Batch
  alias ThistleTea.Game.Entity.Logic.WeaponDamage
  alias ThistleTea.Game.Spell

  def required?(%Spell{id: id}) when id in [2094, 13_099, 13_119, 23_577], do: false
  def required?(%Spell{} = spell), do: Spell.ranged_attack?(spell)

  def validate(%Spell{} = spell, ammo_id, ammo, equipped, count_item) do
    if required?(spell) do
      weapon = Enum.find(equipped, &match?(%{class: 2, inventory_type: type} when type in [15, 25, 26], &1))

      if WeaponDamage.fits?(weapon, spell),
        do: validate_weapon(weapon, ammo_id, ammo, count_item),
        else: {:error, :equipped_item}
    else
      :ok
    end
  end

  def validate(%Character{} = character, %Spell{} = spell, get_item) do
    weapon = get_item.(character.player.ranged)
    ammo = selected_ammo(character, get_item)
    equipped = if match?(%Item{}, weapon) and not Item.broken?(weapon), do: [Item.template(weapon)], else: []
    template = if ammo, do: Item.template(ammo)

    validate(
      spell,
      character.player.ammo_id,
      template,
      equipped,
      &Inventory.count_entry(character.player, &1, get_item)
    )
  end

  def plan(%Character{} = character, %Spell{} = spell, get_item) do
    with :ok <- validate(character, spell, get_item) do
      character.player
      |> Batch.new()
      |> cost(character, spell, get_item)
      |> Inventory.plan(get_item)
    end
  end

  defp cost(batch, character, spell, get_item) do
    if required?(spell) do
      weapon = get_item.(character.player.ranged)

      case Item.template(weapon) do
        %{inventory_type: 25, stackable: 1} -> Batch.update(batch, Durability.lose(weapon, :points, 1))
        %{inventory_type: 25} -> Batch.consume_item(batch, weapon.object.guid, 1)
        %{ammo_type: type} when type in [2, 3] -> Batch.remove(batch, character.player.ammo_id, 1)
        _weapon -> batch
      end
    else
      batch
    end
  end

  defp selected_ammo(%Character{player: player}, get_item) do
    player
    |> Inventory.owned_items(get_item)
    |> Enum.find(&(&1.object.entry == player.ammo_id))
  end

  defp validate_weapon(%{inventory_type: 25}, _ammo_id, _ammo, _count_item), do: :ok
  defp validate_weapon(%{subclass: 19}, _ammo_id, _ammo, _count_item), do: :ok

  defp validate_weapon(%{ammo_type: type}, ammo_id, %{class: 6, subclass: type}, count_item)
       when type in [2, 3] and is_integer(ammo_id) and ammo_id > 0 and is_function(count_item, 1) do
    if count_item.(ammo_id) > 0, do: :ok, else: {:error, :no_ammo}
  end

  defp validate_weapon(_weapon, _ammo_id, _ammo, _count_item), do: {:error, :no_ammo}
end
