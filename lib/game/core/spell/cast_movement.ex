defmodule ThistleTea.Game.Core.Spell.CastMovement do
  @moduledoc "Cast-relative movement and turning rules, including transport frames and self-rooted channels."

  import Bitwise, only: [band: 2]

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Cast
  alias ThistleTea.Game.Core.Spell.Effect

  defstruct [:transport_guid, :position]

  def anchor(%Cast{} = cast, caster), do: %{cast | movement_origin: position(caster)}

  def interrupts?(%Character{} = caster, %Cast{phase: :channel_tick, spell: spell} = cast) do
    MovementBlock.jumping?(caster.movement_block) or
      (flag?(spell.channel_interrupt_flags, 0x10) and turned?(cast.movement_origin, position(caster))) or
      (displaced?(caster, cast) and channel_movement?(spell) and not self_rooted?(caster, spell))
  end

  def interrupts?(%Character{} = caster, %Cast{phase: :preparing, triggered?: false, spell: spell} = cast) do
    is_integer(cast.cast_time_ms) and cast.cast_time_ms > 0 and flag?(spell.interrupt_flags, 0x01) and
      not Spell.attribute?(spell, :on_next_swing) and not Spell.auto_repeat?(spell) and displaced?(caster, cast)
  end

  def interrupts?(_caster, _cast), do: false

  defp displaced?(caster, %Cast{spell: spell, movement_origin: origin}) do
    not Spell.attribute?(spell, :hide_channel_bar) and not falling_recovery?(caster, spell) and
      moved?(origin, position(caster))
  end

  defp channel_movement?(spell) do
    flag?(spell.interrupt_flags, 0x01) or flag?(spell.aura_interrupt_flags, 0x08) or
      flag?(spell.channel_interrupt_flags, 0x08)
  end

  defp falling_recovery?(%Character{movement_block: movement}, %Spell{effects: effects}) do
    MovementBlock.falling_far?(movement) and Enum.any?(effects, &match?(%Effect{index: 0, type: :stuck}, &1))
  end

  defp self_rooted?(%Character{internal: %{rooted?: true}}, %Spell{effects: effects}) do
    Enum.any?(effects, fn effect ->
      effect.type == :apply_aura and effect.aura in [:mod_root, :mod_stun] and effect.implicit_target_a == :caster
    end)
  end

  defp self_rooted?(_caster, _spell), do: false

  defp position(%{movement_block: %MovementBlock{transport_guid: guid, transport_position: {_, _, _, _} = position}})
       when is_integer(guid) and guid > 0, do: %__MODULE__{transport_guid: guid, position: position}

  defp position(%{movement_block: %MovementBlock{position: {_, _, _, _} = position}}),
    do: %__MODULE__{position: position}

  defp position(_caster), do: nil

  defp moved?(%__MODULE__{transport_guid: guid, position: {x, y, z, _}}, %__MODULE__{
         transport_guid: guid,
         position: {current_x, current_y, current_z, _}
       }) do
    abs(current_x - x) > 0.5 or abs(current_y - y) > 0.5 or abs(current_z - z) > 0.5
  end

  defp moved?(%__MODULE__{}, %__MODULE__{}), do: true
  defp moved?(_origin, _current), do: false

  defp turned?(%__MODULE__{transport_guid: guid, position: {_, _, _, orientation}}, %__MODULE__{
         transport_guid: guid,
         position: {_, _, _, current_orientation}
       }), do: orientation != current_orientation

  defp turned?(%__MODULE__{}, %__MODULE__{}), do: true
  defp turned?(_origin, _current), do: false

  defp flag?(flags, mask), do: band(flags || 0, mask) != 0
end
