defmodule ThistleTea.Game.Entity.Logic.ItemSpell do
  @moduledoc "Scripted item outcomes selected before their effects change gameplay state."

  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext

  @six_demon_bag [
    {25, 11_921, :target},
    {25, 13_322, :target},
    {20, 21_179, :target},
    {7, 13_323, :target},
    {3, 13_323, :caster},
    {15, 25_189, :target},
    {5, 14_642, :caster}
  ]

  def six_demon_bag(target, %CastContext{} = context) do
    choices =
      Enum.map(@six_demon_bag, fn {weight, id, recipient} ->
        guid = if recipient == :caster, do: context.caster_guid, else: target.object.guid
        effect = trigger(context, guid, id)
        effect = if recipient == :caster and id == 13_323, do: %{effect | target_role: :other}, else: effect
        {weight, [effect]}
      end)

    {target, [%Effects.RandomChoice{choices: choices}]}
  end

  def resurrection_outcome(%Effects.OfferResurrection{spell: %Spell{id: id}} = offer) when id in [8342, 22_999] do
    {success, failure_id} = if id == 8342, do: {33, 8338}, else: {50, 23_055}
    failure = trigger(offer.cast_context, offer.cast_context.caster_guid, failure_id)
    %Effects.RandomChoice{choices: [{success, [offer]}, {100 - success, [failure]}]}
  end

  def resurrection_outcome(_offer), do: nil

  defp trigger(context, target_guid, spell_id) do
    Effects.trigger_spell(context.caster_guid, context.caster_level, target_guid, spell_id,
      cast_item_guid: context.cast_item_guid,
      resolve_targets?: true
    )
  end
end
