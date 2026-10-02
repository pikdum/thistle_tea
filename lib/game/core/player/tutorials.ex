defmodule ThistleTea.Game.Core.Player.Tutorials do
  @moduledoc """
  The account's 256 seen-tutorial bits, as eight 32-bit words in the order
  `SMSG_TUTORIAL_FLAGS` sends them. A fresh account has seen none.
  """
  import Bitwise, only: [<<<: 2, |||: 2]

  @words 8
  @all_seen 0xFFFFFFFF

  def new, do: List.duplicate(0, @words)
  def all_seen, do: List.duplicate(@all_seen, @words)

  def mark(flags, index) when is_list(flags) and is_integer(index) and index >= 0 and index < @words * 32 do
    List.update_at(flags, div(index, 32), &(&1 ||| 1 <<< rem(index, 32)))
  end

  def mark(flags, _index), do: flags
end
