defmodule ThistleTea.Game.Entity.Logic.PlayerFlags do
  @moduledoc """
  Pure transitions for the public `PLAYER_FLAGS` update field.
  """
  import Bitwise, only: [&&&: 2, |||: 2, bnot: 1]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Player

  @group_leader 0x00000001

  def set_group_leader(%Character{player: %Player{} = player} = character, true) do
    flags = (player.flags || 0) ||| @group_leader
    %{character | player: %{player | flags: flags}}
  end

  def set_group_leader(%Character{player: %Player{} = player} = character, false) do
    flags = (player.flags || 0) &&& bnot(@group_leader)
    %{character | player: %{player | flags: flags}}
  end

  def group_leader?(%Character{player: %Player{flags: flags}}) when is_integer(flags) do
    (flags &&& @group_leader) != 0
  end

  def group_leader?(%Character{}), do: false
end
