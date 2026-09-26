defmodule ThistleTea.Game.Entity.Logic.Warrior do
  @moduledoc """
  Warrior spell behavior that VMangos marks as scripted because DBC effects
  do not carry the required runtime combat values.
  """

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.Combat
  alias ThistleTea.Game.Entity.Logic.CombatWeapon
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.PlayerCombat
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect

  @deep_wounds_percent %{12_162 => 20, 12_850 => 40, 12_868 => 60}
  @deep_wounds_bleed 12_721
  @deep_wounds_ticks 4

  def deep_wounds_tick(caster, spell, now, hand \\ nil)

  def deep_wounds_tick(%{unit: %Unit{}} = caster, %Spell{id: id}, now, hand)
      when is_map_key(@deep_wounds_percent, id) do
    {min_damage, max_damage} = deep_wounds_range(caster, now, hand)
    average = max((min_damage + max_damage) / 2, 0)
    trunc(average * Map.fetch!(@deep_wounds_percent, id) / 100 / @deep_wounds_ticks)
  end

  def deep_wounds_tick(_caster, _spell, _now, _hand), do: nil

  def deep_wounds(%{unit: %Unit{health: health}} = target, %CastContext{deep_wounds_tick: tick} = context)
      when health > 0 and is_integer(tick) and tick >= 0 do
    event =
      Effects.trigger_spell(context.caster_guid, context.caster_level, target.object.guid, @deep_wounds_bleed,
        base_points: tick,
        effect_index: 0,
        resolve_targets?: true,
        requires_living_target?: true,
        triggered_by_spell_id: context.spell.id
      )

    {target, [event]}
  end

  def deep_wounds(target, _context), do: {target, []}

  defp deep_wounds_range(caster, _now, :mainhand), do: Combat.damage_range(caster)

  defp deep_wounds_range(caster, _now, :offhand) do
    if CombatWeapon.usable(caster, :offhand),
      do: Combat.offhand_damage_range(caster) || Combat.damage_range(caster),
      else: Combat.damage_range(caster)
  end

  defp deep_wounds_range(%{internal: %Internal{blackboard: %Blackboard{} = blackboard}} = caster, now, _hand) do
    main = Blackboard.delay_until(blackboard, :next_attack_at, now)
    offhand = Blackboard.delay_until(blackboard, :next_offhand_attack_at, now)
    deep_wounds_range(caster, now, if(main > offhand, do: :offhand, else: :mainhand))
  end

  defp deep_wounds_range(caster, _now, _hand), do: Combat.damage_range(caster)

  def shield_slam_bonus(%Spell{} = spell, %Effect{index: 1}, block_value) do
    if Spell.vmangos_script?(spell, "spell_warrior_shield_slam"), do: max(block_value || 0, 0), else: 0
  end

  def shield_slam_bonus(_spell, _effect, _block_value), do: 0

  def filter_target_effects(effects, target_guid, %CastContext{selected_target_guid: selected}, %Spell{} = spell) do
    if Spell.vmangos_script?(spell, "spell_warrior_intimidating_shout") do
      shout_effects(effects, target_guid == selected)
    else
      effects
    end
  end

  defp shout_effects(effects, true), do: Enum.filter(effects, &(&1.index == 0))
  defp shout_effects(effects, false), do: Enum.reject(effects, &(&1.index == 0))

  def after_energize(%Character{} = character, %Spell{} = spell, now) do
    if Spell.vmangos_script?(spell, "spell_warrior_bloodrage") do
      PlayerCombat.mark_initiated(character, now)
    else
      character
    end
  end

  def after_energize(entity, _spell, _now), do: entity
end
