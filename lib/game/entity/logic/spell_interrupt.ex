defmodule ThistleTea.Game.Entity.Logic.SpellInterrupt do
  @moduledoc "Interrupt eligibility, channel teardown, and school lockouts for landed interrupt effects."

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.CreatureImmunity
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Cooldowns

  def apply(%{internal: %{casting: %Cast{} = cast}} = entity, %CastContext{} = context, %Spell{} = spell, now) do
    if not Core.dead?(entity) and interruptible?(cast) do
      entity =
        entity
        |> Casting.interrupt(now)
        |> lock_school(cast.spell, spell, now)
        |> Core.mark_broadcast_update()

      event = %Effects.SpellInterrupted{
        source_guid: context.caster_guid,
        target_guid: entity.object.guid,
        spell_id: spell.id,
        interrupted_spell_id: cast.spell.id
      }

      {entity, [event]}
    else
      {entity, []}
    end
  end

  def apply(entity, _context, _spell, _now), do: {entity, []}

  defp lock_school(entity, interrupted, interrupt, now) do
    if CreatureImmunity.mechanic?(entity, 9),
      do: entity,
      else: Cooldowns.lock_schools(entity, Spell.school_mask(interrupted), interrupt.duration_ms || 0, now)
  end

  def interruptible?(%Cast{phase: :channel_tick, spell: %Spell{prevention_type: 1, channel_interrupt_flags: flags}})
      when is_integer(flags), do: (flags &&& 0x4) != 0

  def interruptible?(%Cast{phase: :preparing, cast_time_ms: time, spell: %Spell{prevention_type: 1} = spell})
      when is_integer(time) and time > 0, do: Spell.pushback_on_damage?(spell)

  def interruptible?(_cast), do: false
end
