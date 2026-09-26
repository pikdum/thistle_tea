defmodule ThistleTea.Game.Entity.Logic.Consumable do
  @moduledoc """
  Scripted consumable outcomes and periodic animations missing from spell data.
  Each use requests one weighted outcome through the ordinary triggered-spell path.
  """

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Effects.RandomChoice
  alias ThistleTea.Game.Spell.CastContext

  @party_emotes [21, 4, 19, 11]
  @dance 94

  def outcome(%Character{} = entity, %CastContext{} = context, kind) when entity.object.guid == context.caster_guid do
    choices =
      Enum.map(outcomes(kind, entity.unit.gender), fn {weight, spell_id} ->
        effect =
          Effects.trigger_spell(context.caster_guid, context.caster_level, context.caster_guid, spell_id,
            hit_context: context
          )

        {weight, [effect]}
      end)

    [%RandomChoice{choices: choices}]
  end

  def outcome(_entity, _context, _kind), do: []

  def party_emotes(entity) do
    cond do
      Core.dead?(entity) -> []
      MovementBlock.moving?(entity.movement_block) -> emote_choices(@party_emotes)
      true -> emote_choices(@party_emotes ++ [@dance])
    end
  end

  defp outcomes(:noggenfogger, _gender), do: [{2, 16_595}, {2, 16_593}, {6, 16_591}]
  defp outcomes(:deviate_fish, _gender), do: Enum.map([8064, 8065, 8066, 8067, 8068, 8070], &{1, &1})
  defp outcomes(:savory_deviate_delight, 0), do: [{1, 8219}, {1, 8221}]
  defp outcomes(:savory_deviate_delight, _gender), do: [{1, 8220}, {1, 8222}]

  defp emote_choices(ids) do
    [%RandomChoice{choices: Enum.map(ids, &{1, [%Effects.EmoteAnimation{emote_id: &1}]})}]
  end
end
