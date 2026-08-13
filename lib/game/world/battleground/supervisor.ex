defmodule ThistleTea.Game.World.Battleground.Supervisor do
  @moduledoc """
  Supervises isolated battleground match owners.
  """

  alias ThistleTea.Game.World.Battleground.Match

  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(
      strategy: :one_for_one,
      name: Keyword.get(opts, :name, __MODULE__)
    )
  end

  def child_spec(opts) do
    %{id: Keyword.get(opts, :name, __MODULE__), start: {__MODULE__, :start_link, [opts]}, type: :supervisor}
  end

  def start_match(opts, supervisor \\ __MODULE__) do
    DynamicSupervisor.start_child(supervisor, {Match, opts})
  end
end
