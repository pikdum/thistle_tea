defmodule ThistleTea.Game.Core.Aura.DummyFlags do
  @moduledoc """
  Unit flags that vmangos dummy aura handlers set on a creature when the
  aura arrives and clear when it leaves, such as Stoned leaving the statues
  of Uldaman and Blackrock Depths unselectable until they wake.

  The flag follows the transition rather than the holder set, so a flag the
  creature carries for another reason, from its template or a script,
  survives until the aura that claimed it is removed.
  """

  import Bitwise, only: [|||: 2, &&&: 2, bnot: 1]

  alias ThistleTea.Game.Core.Aura.Holder
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Spell

  @unit_flag_not_selectable 0x02000000

  @flags_by_spell %{10_255 => @unit_flag_not_selectable}

  def sync(%Mob{unit: %Unit{} = unit} = mob, previous, current) do
    released = claimed(previous) &&& bnot(claimed(current))
    gained = claimed(current) &&& bnot(claimed(previous))
    %{mob | unit: %{unit | flags: ((unit.flags || 0) &&& bnot(released)) ||| gained}}
  end

  def sync(entity, _previous, _current), do: entity

  defp claimed(holders) do
    Enum.reduce(holders, 0, fn
      %Holder{spell: %Spell{id: id}}, acc when is_map_key(@flags_by_spell, id) -> acc ||| @flags_by_spell[id]
      _holder, acc -> acc
    end)
  end
end
