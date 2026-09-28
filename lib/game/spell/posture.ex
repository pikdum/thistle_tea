defmodule ThistleTea.Game.Spell.Posture do
  @moduledoc "Pure standing and seated-consumption requirements shared by cast admission and launch."

  import Bitwise, only: [band: 2]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Emote
  alias ThistleTea.Game.Spell

  def validate(caster, %Spell{} = spell, opts \\ []) do
    with :ok <- standing(caster, spell, Keyword.get(opts, :triggered?, false)) do
      stationary(caster, spell)
    end
  end

  defp standing(_caster, _spell, true), do: :ok

  defp standing(%{unit: %Unit{}} = caster, spell, false) do
    if Emote.standing?(caster) or Spell.attribute?(spell, :allow_while_sitting),
      do: :ok,
      else: {:error, :not_standing}
  end

  defp standing(_caster, _spell, false), do: :ok

  defp stationary(%Character{movement_block: movement}, spell) do
    if band(spell.aura_interrupt_flags, Aura.interrupt_mask(:stand)) != 0 and MovementBlock.moving?(movement),
      do: {:error, :moving},
      else: :ok
  end

  defp stationary(_caster, _spell), do: :ok
end
