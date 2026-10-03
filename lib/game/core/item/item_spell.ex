defmodule ThistleTea.Game.Core.Item.ItemSpell do
  @moduledoc """
  Scripted item outcomes selected before their effects change gameplay state.

  Self outcomes are items whose use picks one of several spells for the user
  to cast on themselves, like a Dragonmaw Shinbone that usually breaks when
  bent or a Mystic Crystal that tells a resonating skull from bone dust.
  """

  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.CastContext

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

  @self_outcomes %{
    8856 => [{1, 8854}, {4, 8855}],
    17_271 => [{1, 17_269}, {1, 17_270}]
  }

  def self_outcome?(%Spell{id: id}), do: is_map_key(@self_outcomes, id)
  def self_outcome?(_spell), do: false

  def self_outcome(target, %CastContext{caster_guid: guid} = context, %Spell{id: id})
      when is_map_key(@self_outcomes, id) and guid == target.object.guid do
    choices =
      Enum.map(Map.fetch!(@self_outcomes, id), fn {weight, spell_id} ->
        {weight, [Effects.trigger_spell(guid, context.caster_level, guid, spell_id)]}
      end)

    [%Effects.RandomChoice{choices: choices}]
  end

  def self_outcome(_target, _context, _spell), do: []

  defp trigger(context, target_guid, spell_id) do
    Effects.trigger_spell(context.caster_guid, context.caster_level, target_guid, spell_id,
      cast_item_guid: context.cast_item_guid,
      resolve_targets?: true
    )
  end
end
