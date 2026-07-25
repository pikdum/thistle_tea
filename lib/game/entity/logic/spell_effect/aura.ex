defmodule ThistleTea.Game.Entity.Logic.SpellEffect.Aura do
  @moduledoc false

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Hunter
  alias ThistleTea.Game.Entity.Logic.SpellEffect.Amount
  alias ThistleTea.Game.Entity.Logic.Warlock
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Semantics

  def apply_group(target, %CastContext{} = context, now) do
    {target, events} = Aura.apply_spell(target, context, context.spell, now)
    {target, class_events} = Hunter.after_aura(target, context.spell, now)
    {target, events ++ script_trigger_events(target, context) ++ class_events}
  end

  def apply(state, %CastContext{}, _spell, %Effect{type: :persistent_area_aura}, _now), do: {state, []}

  def apply(state, %CastContext{}, _spell, %Effect{type: :dispel_mechanic, misc_value: mechanic}, now)
      when is_integer(mechanic) and mechanic > 0 do
    spell_ids =
      for %Holder{spell: %Spell{id: id, mechanic: ^mechanic}} <- state.unit.auras || [], do: id

    case spell_ids do
      [] -> {state, []}
      ids -> Aura.remove_spells(state, ids, now)
    end
  end

  def apply(state, %CastContext{} = context, spell, %Effect{type: :dispel, misc_value: dispel_type} = effect, now) do
    aura_count = length(state.unit.auras || [])
    count = max(Amount.roll(spell, effect, context), 1)
    {state, events} = Aura.dispel(state, dispel_type, now, dispel_polarity(context), count)

    case {length(state.unit.auras || []) < aura_count, Warlock.devour_magic_heal(spell)} do
      {true, heal_spell_id} when is_integer(heal_spell_id) ->
        {state,
         events ++
           [Effects.trigger_spell(context.caster_guid, context.caster_level, context.caster_guid, heal_spell_id)]}

      _other ->
        {state, events}
    end
  end

  def apply(state, _context, _spell, _effect, _now), do: {state, []}

  defp script_trigger_events(target, %CastContext{spell: spell} = context) do
    with trigger_id when is_integer(trigger_id) <- Semantics.rules(spell).apply_trigger_spell_id,
         true <- Aura.has_spell?(target, spell.id) do
      [Effects.trigger_spell(context.caster_guid, context.caster_level, target.object.guid, trigger_id)]
    else
      _ -> []
    end
  end

  defp dispel_polarity(%CastContext{target_hostile?: true}), do: :positive
  defp dispel_polarity(%CastContext{target_hostile?: false}), do: :negative
  defp dispel_polarity(_context), do: nil
end
