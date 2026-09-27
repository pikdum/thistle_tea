defmodule ThistleTea.Game.Spell.CastTarget do
  @moduledoc "Fresh target facts revalidated before an ordinary cast launches and pays its costs."

  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastValidation
  alias ThistleTea.Game.Spell.CorpseTarget
  alias ThistleTea.Game.Spell.Destination
  alias ThistleTea.Game.Spell.Facing

  defstruct [:targets, :info, :destination_los?]

  def required?(caster, %Spell{} = spell, opts \\ []) do
    ranged? = is_number(spell.range_yards) and spell.range_yards > 0
    (ranged? and not Keyword.get(opts, :triggered?, false)) or Facing.required?(caster, spell, opts)
  end

  def validate(caster, spell, context, opts \\ [])

  def validate(caster, spell, %__MODULE__{targets: targets, info: info, destination_los?: los?}, opts) do
    opts = Keyword.put(opts, :phase, :launch)

    cond do
      Keyword.get(opts, :triggered?, false) ->
        Facing.validate(caster, spell, info, opts)

      CorpseTarget.required?(spell) ->
        :ok

      true ->
        with :ok <- Destination.validate(caster, spell, targets, los?, opts),
             do: CastValidation.validate_target(caster, spell, targets, info, opts)
    end
  end

  def validate(_caster, _spell, _context, _opts), do: :ok
end
