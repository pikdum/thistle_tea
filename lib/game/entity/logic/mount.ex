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

  def validate(%Character{} = character, %Spell{} = spell, opts) do
    cond do
      not is_nil(character.internal.taxi_flight) -> {:error, :not_on_taxi}
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
