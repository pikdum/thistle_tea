defmodule ThistleTea.Game.Entity.Logic.Aura.PlayerSync do
  @moduledoc false
  import Bitwise, only: [|||: 2, <<<: 2, &&&: 2, bnot: 1]

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Logic.CombatRatings

  def sync(%Character{unit: %{auras: holders}, player: %Player{}} = character) when is_list(holders) do
    track_stealthed? = Enum.any?(holders, &Holder.has_aura_type?(&1, :track_stealthed))

    player = %{
      character.player
      | track_creatures: tracking_mask(holders, :track_creatures),
        track_resources: tracking_mask(holders, :track_resources),
        field_bytes_flags: put_flag(character.player.field_bytes_flags, 0x02, track_stealthed?)
    }

    %{character | player: player}
    |> CombatRatings.sync()
  end

  def sync(entity), do: entity

  defp tracking_mask(holders, type) do
    holders
    |> Enum.flat_map(& &1.auras)
    |> Enum.reduce(0, fn
      %Aura{type: ^type, misc_value: value}, mask when is_integer(value) and value in 1..32 ->
        mask ||| 1 <<< (value - 1)

      _aura, mask ->
        mask
    end)
  end

  defp put_flag(flags, flag, true), do: (flags || 0) ||| flag
  defp put_flag(flags, flag, false), do: (flags || 0) &&& bnot(flag)
end
