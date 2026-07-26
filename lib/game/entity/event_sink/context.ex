defmodule ThistleTea.Game.Entity.EventSink.Context do
  @moduledoc """
  Identifies the entity process that receives owner-local effect commands.
  """

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Network

  @enforce_keys [:owner_pid]
  defstruct [:owner_pid]

  def new(owner_pid) when is_pid(owner_pid), do: %__MODULE__{owner_pid: owner_pid}

  def from_entity(%{object: %{guid: guid}}) when is_integer(guid) do
    case Entity.pid(guid) do
      pid when is_pid(pid) -> new(pid)
      _missing -> nil
    end
  end

  def from_entity(_entity), do: nil

  def send(%__MODULE__{owner_pid: owner_pid}, message) do
    Kernel.send(owner_pid, message)
  end

  def send(nil, _message), do: :ok

  def send_after(%__MODULE__{owner_pid: owner_pid}, message, delay_ms) do
    Process.send_after(owner_pid, message, delay_ms)
  end

  def send_after(nil, _message, _delay_ms), do: :ok

  def cast(%__MODULE__{owner_pid: owner_pid}, message) do
    GenServer.cast(owner_pid, message)
  end

  def cast(nil, _message), do: :ok

  def send_packet(%__MODULE__{owner_pid: owner_pid}, message) do
    Network.send_packet(message, owner_pid)
  end

  def send_packet(nil, _message), do: :ok
end
