defmodule ThistleTea.Game.Entity.Logic.CombatState do
  @moduledoc "Shared combat entry, including cast interruption and flag projection."

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.Combat
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast

  def enter(%{unit: %Unit{health: health}, internal: %Internal{} = internal} = entity, now)
      when is_number(health) and health > 0 and is_integer(now) do
    entered = %{entity | internal: %{internal | in_combat: true}}
    entered = if internal.in_combat == true, do: entered, else: interrupt_cast(entered, now)
    Combat.sync_combat_flag(entered)
  end

  def enter(entity, _now), do: entity

  defp interrupt_cast(
         %{internal: %Internal{casting: %Cast{phase: :preparing, cast_time_ms: duration, spell: spell}}} = entity,
         now
       )
       when is_integer(duration) and duration > 0 do
    if Spell.attribute?(spell, :not_in_combat), do: Casting.interrupt(entity, now), else: entity
  end

  defp interrupt_cast(%Mob{internal: %Internal{casting: %Cast{phase: :channel_tick, spell: spell}}} = entity, now) do
    if Bitwise.band(spell.channel_interrupt_flags, 0x01) == 0, do: entity, else: Casting.interrupt(entity, now)
  end

  defp interrupt_cast(entity, _now), do: entity
end
