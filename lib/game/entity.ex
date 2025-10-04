defmodule ThistleTea.Game.Entity do
  def request_update_from(entity_pid, pid \\ self()) do
    GenServer.cast(entity_pid, {:send_update_to, pid})
  end
end
