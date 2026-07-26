defmodule ThistleTea.Game.Entity.Logic.AI.NavigationIntent do
  @moduledoc """
  Typed movement request emitted by behavior logic and resolved by the entity
  owner after the tree finishes evaluating.
  """

  alias ThistleTea.Game.Entity.Data.Component.Internal

  @enforce_keys [:destination]
  defstruct [:destination, opts: []]

  def enqueue(%{internal: %Internal{navigation_intents: intents} = internal} = entity, {_x, _y, _z} = destination, opts)
      when is_list(intents) and is_list(opts) do
    intent = %__MODULE__{destination: destination, opts: opts}
    %{entity | internal: %{internal | navigation_intents: [intent | intents]}}
  end

  def pending?(%{internal: %Internal{navigation_intents: [_ | _]}}), do: true
  def pending?(_entity), do: false

  def drain(%{internal: %Internal{navigation_intents: intents} = internal} = entity) when is_list(intents) do
    {%{entity | internal: %{internal | navigation_intents: []}}, Enum.reverse(intents)}
  end
end
