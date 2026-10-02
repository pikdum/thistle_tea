defmodule ThistleTea.Game.Core.Player.PlayerFlags do
  @moduledoc """
  Pure transitions for the public `PLAYER_FLAGS` update field.
  """
  import Bitwise, only: [&&&: 2, |||: 2, bnot: 1]

  alias ThistleTea.Game.Core.Entity
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Player

  @group_leader 0x00000001
  @contested_pvp 0x00000100
  @hidden %{helm: 0x00000400, cloak: 0x00000800}

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

  def contested_pvp?(%Character{player: %Player{flags: flags}}) when is_integer(flags) do
    (flags &&& @contested_pvp) != 0
  end

  def contested_pvp?(%Character{}), do: false

  def toggle_hidden(%Character{player: %Player{} = player} = character, slot) when is_map_key(@hidden, slot) do
    flags = Bitwise.bxor(player.flags || 0, Map.fetch!(@hidden, slot))
    Entity.mark_broadcast_update(%{character | player: %{player | flags: flags}})
  end

  def hidden?(%Character{player: %Player{flags: flags}}, slot) when is_integer(flags) and is_map_key(@hidden, slot),
    do: (flags &&& Map.fetch!(@hidden, slot)) != 0

  def hidden?(%Character{}, _slot), do: false
end
