defmodule ThistleTea.Game.Entity.Logic.Falling do
  @moduledoc """
  Tracks client-driven falls in world or transport coordinates and applies
  landing damage through the shared health and death transition.
  """

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.DamageImmunity
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Effects

  defstruct [:height, :transport_guid, far?: false]

  def update(%Character{} = character, action, now) do
    movement = character.movement_block

    cond do
      protected?(character) or MovementBlock.swimming?(movement) or action == :swim -> reset(character)
      action == :land -> land(character, now)
      MovementBlock.airborne?(movement) -> track(character)
      true -> reset(character)
    end
  end

  def reset(%{internal: internal} = entity), do: %{entity | internal: %{internal | fall: nil}}

  defp track(%Character{internal: internal, movement_block: movement} = character) do
    {transport_guid, height} = coordinates(movement)
    far? = ((movement.movement_flags || 0) &&& 0x00004000) != 0

    fall =
      case internal.fall do
        %__MODULE__{transport_guid: ^transport_guid} = fall ->
          %{fall | height: max(fall.height, height), far?: fall.far? or far?}

        _ ->
          %__MODULE__{height: height, transport_guid: transport_guid, far?: far?}
      end

    %{character | internal: %{internal | fall: fall}}
  end

  defp land(%Character{internal: %{fall: %__MODULE__{far?: true} = fall}} = character, now) do
    {transport_guid, height} = coordinates(character.movement_block)
    character = reset(character)

    if transport_guid == fall.transport_guid and (character.movement_block.fall_time || 0) >= 1229 do
      apply_damage(character, fall.height - height, now)
    else
      character
    end
  end

  defp land(character, _now), do: reset(character)

  defp apply_damage(character, distance, now) when distance >= 14.57 do
    safe_fall = Aura.flat_amount(character, :safe_fall)
    multiplier = Aura.percent_multiplier(character, :mod_damage_percent_taken, 1)
    max_health = character.unit.max_health
    damage = trunc((0.018 * (distance - safe_fall) - 0.2426) * max_health * multiplier)
    damage = damage |> max(0) |> min(max_health)

    if damage > 0 do
      character
      |> Effects.enqueue(Effects.environmental_damage(:fall, damage))
      |> Core.take_damage(damage, now, environmental?: true)
    else
      character
    end
  end

  defp apply_damage(character, _distance, _now), do: character

  defp protected?(character) do
    not Death.alive?(character) or character.internal.godmode or
      not is_nil(character.internal.taxi_flight) or Aura.has_aura?(character, :feather_fall) or
      Aura.has_aura?(character, :hover) or DamageImmunity.immune?(character, :physical)
  end

  defp coordinates(%MovementBlock{transport_guid: guid, transport_position: {_, _, z, _}})
       when is_integer(guid) and guid > 0, do: {guid, z}

  defp coordinates(%MovementBlock{position: {_, _, z, _}}), do: {nil, z}
end
