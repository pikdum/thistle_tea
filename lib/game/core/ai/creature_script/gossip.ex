defmodule ThistleTea.Game.Core.AI.CreatureScript.Gossip do
  @moduledoc """
  A gossip menu that a vmangos C++ `GossipHello` builds in code, kept as data.
  It replaces the creature's database menu.

  The greeting is the last of `texts` whose condition holds, or the first
  text with no condition when none does. Each option shows while its condition
  holds. Picking one closes the window and runs the option's steps on the
  creature with the player as their target, as a `GossipSelect` handler does.
  """

  defstruct texts: [], options: []

  defmodule Text do
    @moduledoc false
    @enforce_keys [:text_id]
    defstruct [:text_id, :condition]
  end

  defmodule Option do
    @moduledoc false
    @enforce_keys [:text]
    defstruct [:text, :condition, icon: 0, steps: []]
  end
end
