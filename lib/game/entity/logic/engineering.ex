defmodule ThistleTea.Game.Entity.Logic.Engineering do
  @moduledoc "Scripted engineering outcomes expressed as ordinary spell requests."

  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell.CastContext

  def net_o_matic(target, %CastContext{} = context) do
    choices =
      Enum.map([{1, 16_566}, {1, 13_119}, {8, 13_099}], fn {weight, spell_id} ->
        trigger =
          Effects.trigger_spell(context.caster_guid, context.caster_level, target.object.guid, spell_id,
            resolve_targets?: true,
            hit_context: context
          )

        {weight, [trigger]}
      end)

    {target, [%Effects.RandomChoice{choices: choices}]}
  end

  def net_backfire(entity, %CastContext{} = context) do
    trigger =
      Effects.trigger_spell(context.caster_guid, context.caster_level, context.caster_guid, 13_138,
        target_role: :other,
        hit_context: context
      )

    {entity, [trigger]}
  end
end
