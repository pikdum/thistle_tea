defmodule ThistleTea.Game.Entity.Logic.Combat do
  @moduledoc """
  Melee auto-attack logic shared by players and mobs: attack timing, damage
  rolls from unit damage ranges, and applying an incoming attack to an entity
  along with the events it produces.
  """
  import Bitwise, only: [band: 2, bnot: 1, bor: 2]

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Math

  @default_attack_speed_ms 2000
  @default_damage 2
  @unit_flag_in_combat 0x00080000

  @base_melee_range_offset 1.333
  @attack_distance 5.0
  @chase_distance_inset 0.5
  @chase_rechase_range_factor 0.75

  def attack_speed_ms(%{unit: %Unit{base_attack_time: attack_time}}) when is_integer(attack_time) and attack_time > 0 do
    attack_time
  end

  def attack_speed_ms(_entity), do: @default_attack_speed_ms

  def sync_combat_flag(%{unit: %Unit{} = unit, internal: %Internal{in_combat: in_combat}} = entity) do
    updated = combat_flags(unit.flags || 0, in_combat)

    if updated == unit.flags do
      entity
    else
      %{entity | unit: %{unit | flags: updated}}
      |> Core.mark_broadcast_update()
    end
  end

  def sync_combat_flag(entity), do: entity

  defp combat_flags(flags, true), do: bor(flags, @unit_flag_in_combat)
  defp combat_flags(flags, in_combat) when in_combat in [false, nil], do: band(flags, bnot(@unit_flag_in_combat))

  def melee_reach(attacker_reach, target_reach) when is_number(attacker_reach) and is_number(target_reach) do
    max(attacker_reach + target_reach + @base_melee_range_offset, @attack_distance)
  end

  def chase_target_distance(melee_reach) when is_number(melee_reach) do
    max(melee_reach - @chase_distance_inset, 0.0)
  end

  def chase_rechase_distance(melee_reach, target_bounding_radius)
      when is_number(melee_reach) and is_number(target_bounding_radius) do
    max(melee_reach * @chase_rechase_range_factor - target_bounding_radius, 0.0)
  end

  def damage_range(%{
        unit: %Unit{min_damage: min_damage, max_damage: max_damage},
        internal: %Internal{creature: %Creature{damage_multiplier: damage_multiplier}}
      })
      when is_number(min_damage) and is_number(max_damage) do
    multiplier = damage_multiplier(damage_multiplier)

    {min_damage * multiplier, max_damage * multiplier}
  end

  def damage_range(%{unit: %Unit{min_damage: min_damage, max_damage: max_damage}})
      when is_number(min_damage) and is_number(max_damage) do
    {min_damage, max_damage}
  end

  def damage_range(_entity), do: {@default_damage, @default_damage}

  def attack_damage(%{damage: damage}) when is_number(damage), do: trunc(damage)

  def attack_damage(%{min_damage: min_damage, max_damage: max_damage})
      when is_number(min_damage) and is_number(max_damage) do
    min_value = min(min_damage, max_damage)
    max_value = max(min_damage, max_damage)
    Math.random_int(min_value, max_value)
  end

  def attack_damage(_attack), do: @default_damage

  defp damage_multiplier(multiplier) when is_number(multiplier) and multiplier > 0, do: multiplier
  defp damage_multiplier(_multiplier), do: 1.0

  def finalize_attack(attack) when is_map(attack) do
    Map.put_new(attack, :damage, attack_damage(attack))
  end

  def finalize_attack(attack), do: attack

  def attack_start(attacker, target) when is_integer(attacker) and is_integer(target) do
    Event.attack_start(attacker, target)
  end

  def attacker_state_update(attacker, target, damage, attack \\ %{}) when is_integer(attacker) and is_integer(target) do
    Event.attacker_state_update(attacker, target, damage, attack)
  end

  def receive_attack(%{object: %{guid: target_guid}} = entity, attack, now)
      when is_map(attack) and is_integer(target_guid) and is_integer(now) do
    damage = attack_damage(attack)
    entity = Core.take_damage(entity, damage, now)
    event = attacker_state_update(Map.get(attack, :caster, 0), target_guid, damage, attack)

    {entity, reaction_events} = attack_reactions(entity, attack)
    {entity, [event | reaction_events]}
  end

  def receive_attack(entity, _attack, _now), do: {entity, []}

  defp attack_reactions(entity, %{caster: attacker_guid}) when is_integer(attacker_guid) do
    if Core.dead?(entity) do
      {entity, []}
    else
      Aura.reactions(entity, :hit_taken, %{attacker_guid: attacker_guid})
    end
  end

  defp attack_reactions(entity, _attack), do: {entity, []}
end
