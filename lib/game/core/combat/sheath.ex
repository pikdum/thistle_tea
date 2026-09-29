defmodule ThistleTea.Game.Core.Combat.Sheath do
  @moduledoc """
  Weapon sheath state, the sheath byte of `UNIT_FIELD_BYTES_2`: unarmed (0),
  melee (1), or ranged (2).

  `put/2` writes the byte and marks the unit for its next values update, as
  VMangos `Unit::SetSheath` does for scripts. `request/3` is a player's
  sheath toggle, following VMangos HandleSetSheathedOpcode: an unknown state
  is ignored, and a valid one first interrupts channels and removes auras
  that break on sheathing.
  """
  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Spell.Casting

  @states 0..2

  def request(%{unit: %Unit{}} = entity, sheath_state, now) when sheath_state in @states and is_integer(now) do
    mask = Aura.interrupt_mask(:sheathing)
    {entity, events} = entity |> Casting.interrupt_channel(mask, now) |> Aura.remove_with_interrupt_flags(mask, now)

    entity
    |> Effects.enqueue(events)
    |> put(sheath_state)
  end

  def request(entity, _sheath_state, _now), do: entity

  def put(%{unit: %Unit{sheath_state: sheath_state}} = entity, sheath_state), do: entity

  def put(%{unit: %Unit{} = unit} = entity, sheath_state) when sheath_state in @states do
    %{entity | unit: %{unit | sheath_state: sheath_state}} |> Entity.mark_broadcast_update()
  end

  def put(entity, _sheath_state), do: entity
end
