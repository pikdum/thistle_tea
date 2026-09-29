defmodule ThistleTea.Game.Core.Spell.Posture do
  @moduledoc "Pure standing and seated-consumption requirements shared by cast admission and launch."

  import Bitwise, only: [band: 2]

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Chat.Emote
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Spell

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
