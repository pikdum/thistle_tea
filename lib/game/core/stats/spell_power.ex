defmodule ThistleTea.Game.Core.Stats.SpellPower do
  @moduledoc """
  Derives spell power and client damage bonus fields from equipment, active
  auras, and current spirit. Cast snapshots and player projections share the
  same school and weapon restrictions.
  """
  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Aura.Holder
  alias ThistleTea.Game.Core.Combat.WeaponDamage
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Spell

  @schools [:physical, :holy, :fire, :nature, :frost, :shadow, :arcane]

  def bonuses(entity) do
    unrestricted = unrestricted(entity)

    Map.new(@schools, fn school ->
      {positive, negative} = parts(unrestricted, school)
      {school, positive + negative}
    end)
  end

  def recompute(%{unit: %Unit{}, player: %Player{} = player} = entity) do
    unrestricted = unrestricted(entity)

    player =
      Enum.reduce(@schools, player, fn school, current ->
        source = if school == :physical, do: entity, else: unrestricted
        {positive, negative} = parts(source, school)
        multiplier = WeaponDamage.multiplier(unrestricted, school, nil)

        struct!(current, [
          {:"mod_damage_done_pos_#{school}", positive},
          {:"mod_damage_done_neg_#{school}", negative},
          {:"mod_damage_done_pct_#{school}", multiplier}
        ])
      end)

    %{entity | player: player}
  end

  def recompute(entity), do: entity

  defp parts(entity, school) do
    values = [equipment(entity, school), from_spirit(entity, school) | flat_amounts(entity, school)]
    Enum.reduce(values, {0, 0}, &add_amount/2)
  end

  defp add_amount(amount, {positive, negative}) when amount < 0, do: {positive, negative + amount}
  defp add_amount(amount, {positive, negative}), do: {positive + amount, negative}

  defp equipment(%{unit: %Unit{equipment_bonuses: bonuses}}, school) when is_map(bonuses),
    do: Map.get(bonuses, :"spell_#{school}", 0)

  defp equipment(_entity, _school), do: 0

  defp from_spirit(%{unit: %Unit{spirit: spirit}} = entity, school) do
    percent = Aura.flat_modifier(entity, :mod_spell_damage_of_stat_percent, Spell.school_mask(school))
    if percent > 0, do: trunc((spirit || 0) * percent / 100), else: 0
  end

  defp from_spirit(_entity, _school), do: 0

  defp flat_amounts(%{unit: %Unit{auras: holders}}, school) when is_list(holders) do
    mask = Spell.school_mask(school)

    for %Holder{} = holder <- holders,
        %Aura{type: :mod_damage_done, amount: amount, misc_value: schools} <- holder.auras,
        is_integer(amount) and is_integer(schools) and (mask &&& schools) != 0,
        do: amount * max(holder.stacks || 1, 1)
  end

  defp flat_amounts(_entity, _school), do: []

  defp unrestricted(%{unit: %Unit{auras: holders}} = entity) when is_list(holders) do
    holders =
      Enum.filter(holders, fn
        %Holder{spell: %Spell{} = spell} ->
          spell.equipped_item_class in [nil, -1] and spell.equipped_item_inventory_type_mask in [nil, 0]

        %Holder{} ->
          true
      end)

    %{entity | unit: %{entity.unit | auras: holders}}
  end

  defp unrestricted(entity), do: entity
end
