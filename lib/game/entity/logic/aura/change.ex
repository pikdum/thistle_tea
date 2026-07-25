defmodule ThistleTea.Game.Entity.Logic.Aura.Change do
  @moduledoc """
  Describes one complete aura-holder transition and why it happened.
  """

  alias ThistleTea.Game.Aura.Holder

  @causes [
    :applied,
    :expired,
    :dispelled,
    :consumed,
    :death,
    :duel_end,
    :cancelled,
    :delayed,
    :interrupted,
    :removed,
    :ticked
  ]

  @enforce_keys [:holders, :cause, :now]
  defstruct [:holders, :cause, :now]

  @type cause ::
          :applied
          | :expired
          | :dispelled
          | :consumed
          | :death
          | :duel_end
          | :cancelled
          | :delayed
          | :interrupted
          | :removed
          | :ticked

  @type t :: %__MODULE__{
          holders: [Holder.t()],
          cause: cause(),
          now: integer()
        }

  def causes, do: @causes
end
