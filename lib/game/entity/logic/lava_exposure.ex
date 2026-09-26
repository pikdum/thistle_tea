defmodule ThistleTea.Game.Entity.Logic.LavaExposure do
  @moduledoc "Lava contact grace, brief recovery above the surface, and repeated environmental fire damage."

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.EnvironmentalDamage
  alias ThistleTea.Game.Terrain.Liquid

  defstruct [:remaining, :updated_at, :next_damage_at, scale: -1]

  @grace_ms 1_000
  @pulse_ms 2_000

  def next_tick_at(%Character{internal: %Internal{lava_exposure: %__MODULE__{} = timer}}) do
    if timer.scale < 0 do
      timer.next_damage_at || timer.updated_at + timer.remaining
    else
      timer.updated_at + div(@grace_ms - timer.remaining + timer.scale - 1, timer.scale)
    end
  end

  def next_tick_at(_entity), do: nil

  def update(%Character{} = character, liquid, now, damage, resistance_roll) do
    if is_nil(liquid) or protected?(character) do
      put_timer(character, nil)
    else
      {_, _, z, _} = character.movement_block.position
      advance(character, Liquid.magma?(liquid) and Liquid.touching?(liquid, z), now, damage, resistance_roll)
    end
  end

  defp protected?(character) do
    not Death.alive?(character) or character.internal.godmode or character.unit.shapeshift_form == 32
  end

  defp advance(%Character{internal: %Internal{lava_exposure: nil}} = character, true, now, _damage, _roll),
    do: put_timer(character, %__MODULE__{remaining: @grace_ms, updated_at: now})

  defp advance(%Character{internal: %Internal{lava_exposure: nil}} = character, false, _now, _damage, _roll),
    do: character

  defp advance(%Character{internal: %Internal{lava_exposure: previous}} = character, touching?, now, damage, roll) do
    remaining = previous.remaining + max(now - previous.updated_at, 0) * previous.scale

    timer = %{
      previous
      | remaining: remaining |> max(0) |> min(@grace_ms),
        updated_at: now,
        scale: if(touching?, do: -1, else: 10),
        next_damage_at: if(touching?, do: previous.next_damage_at)
    }

    cond do
      not touching? and timer.remaining == @grace_ms -> put_timer(character, nil)
      touching? and timer.remaining == 0 -> maybe_burn(put_timer(character, timer), now, damage, roll)
      true -> put_timer(character, timer)
    end
  end

  defp maybe_burn(%Character{internal: %Internal{lava_exposure: timer}} = character, now, damage, roll) do
    if is_nil(timer.next_damage_at) or now >= timer.next_damage_at do
      character =
        character
        |> put_timer(%{timer | next_damage_at: now + @pulse_ms})
        |> EnvironmentalDamage.apply(:lava, damage, now, roll: roll)

      if Death.alive?(character), do: character, else: put_timer(character, nil)
    else
      character
    end
  end

  defp put_timer(character, timer), do: %{character | internal: %{character.internal | lava_exposure: timer}}
end
