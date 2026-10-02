defmodule ThistleTea.Game.Inbound.CmsgUpdateAccountData do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, opcode: :CMSG_UPDATE_ACCOUNT_DATA, while_possessed: true

  alias ThistleTea.Game.Network.ConnectionState
  alias ThistleTea.Game.World.Entity.Player.AccountCaches

  defstruct [:type, :data]

  @impl ClientMessage
  def from_binary(<<type::little-size(32), 0::little-size(32), _rest::binary>>), do: %__MODULE__{type: type, data: ""}

  def from_binary(<<type::little-size(32), size::little-size(32), compressed::binary>>),
    do: %__MODULE__{type: type, data: inflate(compressed, size)}

  @impl ClientMessage
  def handle(%__MODULE__{data: nil}, state), do: state

  def handle(%__MODULE__{type: type, data: data}, %ConnectionState{account: %{id: account_id}} = state) do
    AccountCaches.store(account_id, state.character_guid, type, data)
    state
  end

  def handle(%__MODULE__{type: type, data: data}, %{account: %{id: account_id}, character: character} = state) do
    AccountCaches.store(account_id, character.object.guid, type, data)
    state
  end

  def handle(%__MODULE__{}, state), do: state

  defp inflate(compressed, size) do
    z = :zlib.open()

    try do
      :ok = :zlib.inflateInit(z)
      data = z |> :zlib.inflate(compressed) |> IO.iodata_to_binary()
      if byte_size(data) == size, do: data
    catch
      _kind, _reason -> nil
    after
      :zlib.close(z)
    end
  end
end
