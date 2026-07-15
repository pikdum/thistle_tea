defmodule ThistleTea.Game.Entity.Logic.Exploration do
  @moduledoc """
  Pure world-map exploration bitfield transitions and XP calculation.
  """
  import Bitwise, only: [&&&: 2, |||: 2, <<<: 2]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Player

  @explored_zone_words 64
  @word_bits 32
  @byte_bits 8
  @explored_zone_bytes div(@explored_zone_words * @word_bits, @byte_bits)
  @max_area_bit @explored_zone_words * @word_bits - 1

  def discover(%Character{player: %Player{} = player} = character, area_bit)
      when is_integer(area_bit) and area_bit >= 0 and area_bit <= @max_area_bit do
    explored_zones = normalize(player.explored_zones)

    if bit_set?(explored_zones, area_bit) do
      :already_explored
    else
      player = %{player | explored_zones: put_bit(explored_zones, area_bit)}
      {:ok, %{character | player: player}}
    end
  end

  def discover(%Character{}, _area_bit), do: {:error, :invalid_area_bit}

  def explored?(%Character{player: %Player{explored_zones: explored_zones}}, area_bit)
      when is_integer(area_bit) and area_bit >= 0 and area_bit <= @max_area_bit do
    explored_zones
    |> normalize()
    |> bit_set?(area_bit)
  end

  def explored?(%Character{}, _area_bit), do: false

  def unlock_all(%Character{player: %Player{} = player} = character) do
    %{character | player: %{player | explored_zones: :binary.copy(<<0xFF>>, @explored_zone_bytes)}}
  end

  def experience(player_level, area_level, max_level, base_xp)
      when is_integer(player_level) and is_integer(area_level) and is_integer(max_level) and is_function(base_xp, 1) do
    cond do
      area_level <= 0 or player_level >= max_level ->
        0

      player_level - area_level < -5 ->
        xp_at(base_xp, player_level + 5)

      player_level - area_level > 5 ->
        percentage = max(100 - (player_level - area_level - 5) * 5, 0)
        trunc(xp_at(base_xp, area_level) * percentage / 100)

      true ->
        xp_at(base_xp, area_level)
    end
  end

  defp normalize(explored_zones) when is_binary(explored_zones) and byte_size(explored_zones) == @explored_zone_bytes,
    do: explored_zones

  defp normalize(_explored_zones), do: :binary.copy(<<0>>, @explored_zone_bytes)

  defp bit_set?(explored_zones, area_bit) do
    byte = :binary.at(explored_zones, div(area_bit, @byte_bits))
    (byte &&& 1 <<< rem(area_bit, @byte_bits)) != 0
  end

  defp put_bit(explored_zones, area_bit) do
    byte_index = div(area_bit, @byte_bits)
    byte = :binary.at(explored_zones, byte_index) ||| 1 <<< rem(area_bit, @byte_bits)
    prefix = binary_part(explored_zones, 0, byte_index)
    suffix_start = byte_index + 1
    suffix = binary_part(explored_zones, suffix_start, @explored_zone_bytes - suffix_start)
    prefix <> <<byte>> <> suffix
  end

  defp xp_at(base_xp, level) do
    case base_xp.(level) do
      xp when is_integer(xp) and xp > 0 -> xp
      _ -> 0
    end
  end
end
