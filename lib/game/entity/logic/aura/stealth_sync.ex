defmodule ThistleTea.Game.Entity.Logic.Aura.StealthSync do
  @moduledoc """
  Derives the two client stealth flags from active stealth auras.
  """
  import Bitwise, only: [|||: 2, &&&: 2, bnot: 1]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura

  @unit_vis_creep 0x02
  @player_flag_stealth 0x20

  def sync(%Character{unit: %Unit{} = unit, player: %Player{} = player} = entity) do
    stealthed? = Aura.has_aura?(entity, :mod_stealth)

    unit = %{unit | vis_flag: put_flag(unit.vis_flag, @unit_vis_creep, stealthed?)}
    player = %{player | field_bytes2_flags: put_flag(player.field_bytes2_flags, @player_flag_stealth, stealthed?)}
    %{entity | unit: unit, player: player}
  end

  def sync(%{unit: %Unit{} = unit} = entity) do
    stealthed? = Aura.has_aura?(entity, :mod_stealth)
    %{entity | unit: %{unit | vis_flag: put_flag(unit.vis_flag, @unit_vis_creep, stealthed?)}}
  end

  def sync(entity), do: entity

  defp put_flag(flags, flag, true), do: (flags || 0) ||| flag
  defp put_flag(flags, flag, false), do: (flags || 0) &&& bnot(flag)
end
