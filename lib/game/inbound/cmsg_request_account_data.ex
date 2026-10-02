defmodule ThistleTea.Game.Inbound.CmsgRequestAccountData do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, opcode: :CMSG_REQUEST_ACCOUNT_DATA, while_possessed: true

  alias ThistleTea.Game.Network.ConnectionState
  alias ThistleTea.Game.World.Entity.Player.AccountCaches

  defstruct [:type]

  @impl ClientMessage
  def from_binary(<<type::little-size(32)>>), do: %__MODULE__{type: type}

  @impl ClientMessage
  def handle(%__MODULE__{type: type}, %ConnectionState{account: %{id: account_id}} = state) do
    AccountCaches.send(account_id, state.character_guid, type)
    state
  end

  def handle(%__MODULE__{type: type}, %{account: %{id: account_id}, character: character} = state) do
    AccountCaches.send(account_id, character.object.guid, type)
    state
  end

  def handle(%__MODULE__{}, state), do: state
end
