defmodule ThistleTea.Game.World.System.ElementalInvasion do
  @moduledoc """
  Drives the Elemental Invasion (`Core.GameEvent.ElementalInvasion`). Each
  element's stage and kill tally live in vmangos's server variables, and its
  lord's EventAI marks the stage on death. This process advances stages from
  the invaders a rift reports slain and from an hourly clock, holds a fallen
  lord's event open while the corpse is looted, and calls the next invasion
  two to four days after the last lord falls. A world starts invaded.
  """
  use GenServer

  alias ThistleTea.Game.Core.GameEvent.ElementalInvasion, as: Invasion
  alias ThistleTea.Game.World.ServerVariables
  alias ThistleTea.Game.World.System.GameEvent
  alias ThistleTea.Game.World.Topics

  @hour_ms 3_600_000
  @looting_ms 300_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  def invader_slain(element, server \\ __MODULE__) when is_atom(element) do
    GenServer.cast(server, {:invader_slain, element})
  end

  def stage(%Invasion.Element{stage_variable: variable}, table \\ ServerVariables),
    do: ServerVariables.get(variable, table)

  @impl GenServer
  def init(opts) do
    state = %{
      variables: Keyword.get(opts, :variables, ServerVariables),
      game_events: Keyword.get(opts, :game_events, GameEvent),
      hour_ms: Keyword.get(opts, :hour_ms, @hour_ms),
      looting_ms: Keyword.get(opts, :looting_ms, @looting_ms),
      rest_ms: Keyword.get(opts, :rest_ms, fn -> Enum.random(Invasion.rest_ms()) end),
      looting: MapSet.new(),
      invading?: true
    }

    for element <- Invasion.elements(), do: Topics.subscribe(Topics.server_variable(element.stage_variable))
    Process.send_after(self(), :hour, state.hour_ms)
    {:ok, state |> begin() |> drive()}
  end

  @impl GenServer
  def handle_cast({:invader_slain, name}, state) do
    case Enum.find(Invasion.elements(), &(&1.name == name)) do
      %Invasion.Element{} = element ->
        kills = ServerVariables.get(element.kills_variable, state.variables)
        {stage, kills} = Invasion.slain(stage(element, state.variables), kills)
        :ok = ServerVariables.put(element.kills_variable, kills, state.variables)
        :ok = ServerVariables.put(element.stage_variable, stage, state.variables)
        {:noreply, drive(state)}

      nil ->
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info(:hour, state) do
    Process.send_after(self(), :hour, state.hour_ms)

    for element <- Invasion.elements() do
      :ok =
        ServerVariables.put(element.stage_variable, Invasion.endured(stage(element, state.variables)), state.variables)
    end

    {:noreply, drive(state)}
  end

  def handle_info({:server_variable_changed, variable}, state) do
    element = Invasion.stage_element(variable)

    state =
      if (element && Invasion.boss_down?(stage(element, state.variables))) and element.name not in state.looting do
        Process.send_after(self(), {:looted, element.name}, state.looting_ms)
        %{state | looting: MapSet.put(state.looting, element.name)}
      else
        state
      end

    {:noreply, drive(state)}
  end

  def handle_info({:looted, name}, state) do
    {:noreply, drive(%{state | looting: MapSet.delete(state.looting, name)})}
  end

  def handle_info(:invade, state) do
    {:noreply, state |> begin() |> drive()}
  end

  defp begin(state) do
    for element <- Invasion.elements() do
      :ok = ServerVariables.put(element.kills_variable, 0, state.variables)
      :ok = ServerVariables.put(element.stage_variable, Invasion.first_stage(), state.variables)
    end

    %{state | looting: MapSet.new(), invading?: true}
  end

  defp drive(state) do
    stages = Map.new(Invasion.elements(), &{&1.name, stage(&1, state.variables)})
    events = Invasion.driven(stages, state.looting)
    :ok = GameEvent.drive(events, state.game_events)
    invading? = Enum.any?(events, &elem(&1, 1))

    if state.invading? and not invading?, do: Process.send_after(self(), :invade, state.rest_ms.())

    %{state | invading?: invading?}
  end
end
