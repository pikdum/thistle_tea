defmodule ThistleTea.Game.Entity.Logic.Mount do
  @moduledoc """
  Ground mount cast rules and dismount transitions through the aura owner.
  """
  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext

  @reindeer_transformation 25_860

  def spell?(%Spell{effects: effects}), do: Enum.any?(effects, &(&1.aura == :mounted))

  def prepare_cast(%Character{} = character, %Spell{} = spell, now) do
    if Spell.attribute?(spell, :passive) or Spell.attribute?(spell, :allow_while_mounted) do
      character
    else
      dismount(character, now)
    end
  end

  def prepare_cast(entity, _spell, _now), do: entity

  def dismount(entity, now) do
    {entity, effects} = Aura.remove_aura_types(entity, [:mounted], now)
    Effects.enqueue(entity, effects)
  end

  def reindeer(entity, %CastContext{caster_guid: guid} = context, now) when entity.object.guid == guid do
    if Aura.has_aura?(entity, :mounted) do
      spell_id = if entity.movement_block.run_speed >= 2 * MovementBlock.default_run_speed(), do: 25_859, else: 25_858
      {entity, events} = Aura.remove_aura_types(entity, [:mounted], now)

      trigger =
        Effects.trigger_spell(guid, context.caster_level, guid, spell_id,
          cast_item_guid: context.cast_item_guid,
          hit_context: context
        )

      {entity, events ++ [trigger]}
    else
      {entity, []}
    end
  end

  def reindeer(entity, _context, _now), do: {entity, []}

  def validate(%Character{} = character, %Spell{} = spell, opts) do
    cond do
      not is_nil(character.internal.taxi_flight) -> {:error, :not_on_taxi}
      spell.id == @reindeer_transformation and not Aura.has_aura?(character, :mounted) -> {:error, :only_mounted}
      underwater_restricted?(character, spell) -> {:error, :only_abovewater}
      spell?(spell) and not Keyword.get(opts, :mount_allowed?, true) -> {:error, :no_mounts_allowed}
      true -> :ok
    end
  end

  def validate(_entity, _spell, _opts), do: :ok

  defp underwater_restricted?(character, spell) do
    (spell.aura_interrupt_flags &&& Aura.interrupt_mask(:under_water)) != 0 and
      MovementBlock.swimming?(character.movement_block)
  end
end
