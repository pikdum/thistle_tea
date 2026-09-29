defmodule ThistleTea.Game.Core.Stats.TargetAttackPower do
  @moduledoc """
  Target-dependent attack power for weapon damage. Caster bonuses are
  snapshotted by creature mask; target debuffs are read when the hit lands.
  These bonuses never change the attacker's displayed attack power.
  """
  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Aura.Holder
  alias ThistleTea.Game.Core.Creature.CreatureType
  alias ThistleTea.Game.Core.Entity.Component.Unit

  def snapshot(entity) do
    %{
      melee: amounts(entity, :mod_melee_attack_power_versus),
      ranged: amounts(entity, :mod_ranged_attack_power_versus)
    }
  end

  def bonus(target, snapshot, kind) when kind in [:melee, :ranged] do
    type =
      if kind == :ranged,
        do: :ranged_attack_power_attacker_bonus,
        else: :melee_attack_power_attacker_bonus

    Aura.versus_amount(Map.get(snapshot, kind, []), CreatureType.mask(target)) +
      Aura.flat_amount(target, type)
  end

  def damage(target, snapshot, kind, speed_ms) when is_number(speed_ms) and speed_ms > 0 do
    bonus(target, snapshot, kind) * speed_ms / 14_000
  end

  def damage(_target, _snapshot, _kind, _speed_ms), do: 0.0

  defp amounts(%{unit: %Unit{auras: holders}}, type) when is_list(holders) do
    Enum.flat_map(holders, fn %Holder{auras: auras, stacks: stacks} ->
      Enum.flat_map(auras, fn
        %Aura{type: ^type, amount: amount, misc_value: mask} when is_integer(amount) and is_integer(mask) ->
          [{mask, amount * max(stacks || 1, 1)}]

        _aura ->
          []
      end)
    end)
  end

  defp amounts(_entity, _type), do: []
end
