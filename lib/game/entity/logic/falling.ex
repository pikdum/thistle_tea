defmodule ThistleTea.Game.Entity.Logic.Falling do
  @moduledoc """
  Computes falling trajectories and tracks client-driven landing damage
  through the shared health and death transition.
  """

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.DamageImmunity
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.EnvironmentalDamage

  defstruct [:height, :transport_guid, far?: false]

  @gravity 19.29110527038574
  @terminal_velocity 60.148003
  @terminal_time @terminal_velocity / @gravity
  @terminal_distance @terminal_velocity * @terminal_velocity / (2 * @gravity)

  def duration(distance) when is_number(distance) and distance > 0 do
    seconds =
      if distance >= @terminal_distance,
        do: (distance - @terminal_distance) / @terminal_velocity + @terminal_time,
        else: :math.sqrt(2 * distance / @gravity)

    ceil(seconds * 1_000)
  end

  def distance(elapsed_ms) when is_number(elapsed_ms) and elapsed_ms >= 0 do
    seconds = elapsed_ms / 1_000

    if seconds > @terminal_time,
      do: @terminal_velocity * (seconds - @terminal_time) + @terminal_distance,
      else: @gravity * seconds * seconds / 2
  end

  def position({x, y, z}, {_x, _y, floor}, elapsed_ms), do: {x, y, max(floor, z - distance(elapsed_ms))}

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
      EnvironmentalDamage.apply(character, :fall, damage, now)
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
