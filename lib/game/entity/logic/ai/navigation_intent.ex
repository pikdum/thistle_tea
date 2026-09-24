defmodule ThistleTea.Game.Entity.Logic.AI.NavigationIntent do
  @moduledoc """
  Typed movement request emitted by behavior logic and resolved by the entity
  owner after the tree finishes evaluating.
  """

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Math

  @horizontal_tolerance 0.1
  @floor_tolerance 1.5

  @enforce_keys [:destination]
  defstruct [:destination, :path, opts: []]

  @doc "Accepts navigation floor refinement without treating a different floor or a short path as arrival."
  def reached?({x, y, z}, {tx, ty, tz}) do
    Math.distance({x, y, 0.0}, {tx, ty, 0.0}) <= @horizontal_tolerance and abs(z - tz) <= @floor_tolerance
  end

  def enqueue(%{internal: %Internal{navigation_intents: intents} = internal} = entity, {_x, _y, _z} = destination, opts)
      when is_list(intents) and is_list(opts) do
    intent = %__MODULE__{destination: destination, opts: opts}
    %{entity | internal: %{internal | navigation_intents: [intent | intents]}}
  end

  def pending?(%{internal: %Internal{navigation_intents: [_ | _]}}), do: true
  def pending?(_entity), do: false

  def enqueue_path(%{internal: %Internal{navigation_intents: intents} = internal} = entity, [_ | _] = path, opts)
      when is_list(opts) do
    intent = %__MODULE__{destination: List.last(path), path: path, opts: opts}
    %{entity | internal: %{internal | navigation_intents: [intent | intents]}}
  end

  def enqueue_path(entity, [], _opts), do: entity

  def drain(%{internal: %Internal{navigation_intents: intents} = internal} = entity) when is_list(intents) do
    {%{entity | internal: %{internal | navigation_intents: []}}, Enum.reverse(intents)}
  end
end
