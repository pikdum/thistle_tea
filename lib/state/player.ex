defmodule ThistleTea.PlayerStorage do
  use GenServer

  require Logger

  import ThistleTea.Game.UpdateObject

  def start_link(initial) do
    GenServer.start_link(__MODULE__, initial)
  end

  def update_movement(pid, movement) do
    GenServer.cast(pid, {:update_movement, movement})
  end

  @impl true
  def init(initial) do
    {:ok, initial}
  end

  @impl true
  def handle_cast({:update_movement, movement}, state) do
    decoded = decode_movement_info(movement)
    Logger.info("[Player] Decoded Movement Info: #{inspect(decoded)}")
    Map.put(state, :movement, decoded)
    {:noreply, state}
  end
end
