defmodule ThistleTea.Game.Entity.Logic.Hunter do
  @moduledoc """
  Pure Hunter ranged-ammunition rules derived from the equipped weapon and
  selected projectile item.
  """
  import Bitwise, only: [&&&: 2, <<<: 2]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Entity.Logic.PlayerCombat
  alias ThistleTea.Game.Spell

  @item_class_projectile 6

  def validate_ammo(%Spell{} = spell, ammo_id, ammo_template, equipped_items, count_item)
      when is_list(equipped_items) do
    if Spell.ranged_ability?(spell) do
      validate_projectile(ammo_id, ammo_template, ranged_weapon(equipped_items), count_item)
    else
      :ok
    end
  end

  def ammo_reagents(%{player: %{ammo_id: ammo_id}}, %Spell{} = spell) when is_integer(ammo_id) and ammo_id > 0 do
    if Spell.ranged_ability?(spell), do: [{ammo_id, 1}], else: []
  end

  def ammo_reagents(_character, _spell), do: []

  def validate_tame(caster, %Spell{} = spell, target) do
    if tame_creature?(spell), do: validate_tame_target(caster, target), else: :ok
  end

  def validate_feed(%Spell{} = spell, feed_context) do
    if feed_pet?(spell), do: validate_feed_context(feed_context), else: :ok
  end

  def feed_benefit(%{item: %{item_level: item_level}, pet: %{level: pet_level}} = feed_context) do
    with :ok <- validate_feed_context(feed_context) do
      {:ok, food_benefit(pet_level, item_level)}
    end
  end

  def feed_benefit(feed_context), do: validate_feed_context(feed_context)

  def food_allowed?(food_mask, food_type) when is_integer(food_mask) and is_integer(food_type) and food_type in 1..8 do
    (food_mask &&& 1 <<< (food_type - 1)) != 0
  end

  def food_allowed?(_food_mask, _food_type), do: false

  def food_benefit(pet_level, item_level) when is_integer(pet_level) and is_integer(item_level) do
    cond do
      pet_level <= item_level + 5 -> 35_000
      pet_level <= item_level + 10 -> 17_000
      pet_level <= item_level + 14 -> 8_000
      true -> 0
    end
  end

  def food_benefit(_pet_level, _item_level), do: 0

  def apply_food_benefit(%Spell{} = spell, benefit) when is_integer(benefit) and benefit > 0 do
    effects =
      Enum.map(spell.effects, fn
        %Spell.Effect{type: :apply_aura, aura: :periodic_energize} = effect ->
          %{effect | base_points: benefit, die_sides: 0}

        effect ->
          effect
      end)

    %{spell | effects: effects}
  end

  def apply_food_benefit(%Spell{} = spell, _benefit), do: spell

  def after_aura(%Character{} = character, %Spell{} = spell, now) do
    if feign_death?(spell), do: apply_feign_death(character, now), else: {character, []}
  end

  def after_aura(entity, _spell, _now), do: {entity, []}

  defp apply_feign_death(character, now) do
    {character, mob_guids} = PlayerCombat.vanish(character, now)

    events =
      [Event.drop_nearby_threat()] ++
        Enum.map(mob_guids, &Event.drop_threat/1) ++ attack_stop_events(character)

    character =
      character
      |> BT.clear_auto_attack()
      |> then(&%{&1 | internal: %{&1.internal | auto_shot: nil}})
      |> then(&%{&1 | unit: %{&1.unit | stand_state: 7}})

    {character, events ++ [Event.stand_state(7)]}
  end

  defp validate_feed_context(nil), do: {:error, :no_pet}

  defp validate_feed_context(%{item: nil}), do: {:error, :bad_targets}
  defp validate_feed_context(%{pet: nil}), do: {:error, :no_pet}

  defp validate_feed_context(%{
         item: %{food_type: food_type, item_level: item_level},
         pet: %{alive?: alive?, in_combat: in_combat, food_mask: food_mask, level: pet_level}
       }) do
    cond do
      not alive? -> {:error, :targets_dead}
      in_combat -> {:error, :affecting_combat}
      not food_allowed?(food_mask, food_type) -> {:error, :wrong_pet_food}
      food_benefit(pet_level, item_level) == 0 -> {:error, :food_lowlevel}
      true -> :ok
    end
  end

  defp validate_feed_context(_context), do: {:error, :bad_targets}

  defp validate_tame_target(%{unit: %{summon: summon}}, _target) when is_integer(summon) and summon > 0,
    do: {:error, :already_have_summon}

  defp validate_tame_target(%{unit: %{level: level}}, %{tameable?: true, level: target_level})
       when is_integer(level) and is_integer(target_level) and target_level <= level, do: :ok

  defp validate_tame_target(_caster, _target), do: {:error, :bad_targets}

  defp tame_creature?(%Spell{effects: effects}), do: Enum.any?(effects, &(&1.type == :tame_creature))
  defp feed_pet?(%Spell{effects: effects}), do: Enum.any?(effects, &(&1.type == :feed_pet))

  defp feign_death?(%Spell{effects: effects}) do
    Enum.any?(effects, &(&1.type in [:apply_aura, :apply_area_aura] and &1.aura == :feign_death))
  end

  defp validate_projectile(_ammo_id, _ammo, %{ammo_type: 0}, _count_item), do: :ok

  defp validate_projectile(
         ammo_id,
         %{class: @item_class_projectile, subclass: subclass},
         %{ammo_type: subclass},
         count_item
       )
       when is_integer(ammo_id) and ammo_id > 0 and is_function(count_item, 1) do
    if count_item.(ammo_id) > 0, do: :ok, else: {:error, :no_ammo}
  end

  defp validate_projectile(_ammo_id, _ammo, _weapon, _count_item), do: {:error, :no_ammo}

  defp ranged_weapon(items),
    do: Enum.find(items, &match?(%{class: 2, inventory_type: type} when type in [15, 25, 26], &1))

  defp attack_stop_events(%Character{object: %{guid: guid}, unit: %{target: target}})
       when is_integer(target) and target > 0, do: [Event.attack_stop(guid, target)]

  defp attack_stop_events(_character), do: []
end
