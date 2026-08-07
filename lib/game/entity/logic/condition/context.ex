defmodule ThistleTea.Game.Entity.Logic.Condition.Context do
  @moduledoc """
  Immutable semantic facts supplied to the condition evaluator by an owning
  boundary.
  """

  alias ThistleTea.Game.Entity.Logic.Condition.Subject

  defstruct source: nil,
            target: nil,
            world: %{},
            now: nil,
            content_patch: nil,
            quests: %{},
            environment: %{}

  def new(options \\ []) when is_list(options) do
    struct!(__MODULE__, options)
  end

  def for_subject(%Subject{} = subject, options \\ []) do
    options
    |> Keyword.put_new(:source, subject)
    |> Keyword.put_new(:target, subject)
    |> new()
  end

  def swap(%__MODULE__{} = context) do
    %{context | source: context.target, target: context.source}
  end
end
