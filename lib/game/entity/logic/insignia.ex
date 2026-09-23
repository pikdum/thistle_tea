defmodule ThistleTea.Game.Entity.Logic.Insignia do
  @moduledoc "Battleground body eligibility, removal admission, and corpse money rewards."

  import Bitwise, only: [&&&: 2, |||: 2, bnot: 1]

  alias ThistleTea.Game.Battleground
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Spell

  @skinnable 0x04000000
  @range 10.0

  def range, do: @range

  def spell?(%Spell{effects: effects}), do: Enum.any?(effects, &(&1.type == :remove_insignia))

  def prepare(%Character{} = character, battleground?) do
    flags = (character.unit.flags || 0) &&& bnot(@skinnable)
    flags = if battleground? and Core.dead?(character), do: flags ||| @skinnable, else: flags
    put_flags(character, flags)
  end

  def clear(%Character{} = character) do
    put_flags(character, (character.unit.flags || 0) &&& bnot(@skinnable))
  end

  def clear(entity), do: entity

  def available?(%Character{} = character) do
    Core.dead?(character) and not Death.ghost?(character) and ((character.unit.flags || 0) &&& @skinnable) != 0
  end

  def projection(%Character{} = character) do
    %{
      team: Battleground.team_for_race(character.unit.race),
      available?: available?(character),
      death_id: character.internal.corpse_reclaim.expires_at,
      level: character.unit.level
    }
  end

  def validate(%Character{} = caster, %{} = body) do
    {cx, cy, cz, _orientation} = caster.movement_block.position

    actor = %{
      position: {caster.internal.world, cx, cy, cz},
      team: Battleground.team_for_race(caster.unit.race),
      alive?: Death.alive?(caster)
    }

    validate_actor(actor, body)
  end

  def validate(_caster, _body), do: {:error, :bad_targets}

  def validate_actor(
        %{position: {caster_world, cx, cy, cz}, team: caster_team, alive?: alive?},
        %{position: {world, x, y, z}, team: team} = body
      ) do
    cond do
      not alive? -> {:error, :caster_dead}
      world != caster_world -> {:error, :bad_targets}
      not opponents?(team, caster_team) -> {:error, :target_friendly}
      Map.get(body, :available?) != true -> {:error, :target_unskinnable}
      Map.get(body, :visible?) != true -> {:error, :bad_targets}
      Map.get(body, :los?) != true -> {:error, :line_of_sight}
      (cx - x) ** 2 + (cy - y) ** 2 + (cz - z) ** 2 > @range * @range -> {:error, :out_of_range}
      true -> :ok
    end
  end

  def validate_actor(_actor, _body), do: {:error, :bad_targets}

  def gold(level, roll) when level in 1..60 and roll in 50..150 do
    trunc(roll * 0.016 * :math.pow(level / 5.76, 2.5))
  end

  defp opponents?(:alliance, :horde), do: true
  defp opponents?(:horde, :alliance), do: true
  defp opponents?(_team, _caster_team), do: false

  defp put_flags(%Character{unit: %{flags: nil}} = character, 0), do: character
  defp put_flags(character, flags), do: %{character | unit: %{character.unit | flags: flags}}
end
