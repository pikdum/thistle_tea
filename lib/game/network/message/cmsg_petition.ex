defmodule ThistleTea.Game.Network.Message.CmsgPetitionShowlist do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_PETITION_SHOWLIST

  alias ThistleTea.Game.Player.Petitions

  defstruct [:npc_guid]

  @impl ClientMessage
  def handle(%__MODULE__{npc_guid: guid}, state), do: Petitions.show_list(state, guid)

  @impl ClientMessage
  def from_binary(<<guid::little-size(64), _rest::binary>>), do: %__MODULE__{npc_guid: guid}
end

defmodule ThistleTea.Game.Network.Message.CmsgPetitionBuy do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_PETITION_BUY

  alias ThistleTea.Game.Player.Petitions

  defstruct [:npc_guid, :name]

  @impl ClientMessage
  def handle(%__MODULE__{npc_guid: guid, name: name}, state), do: Petitions.buy(state, guid, name)

  @impl ClientMessage
  def from_binary(<<guid::little-size(64), _unknown::little-size(32), _unknown_guid::little-size(64), rest::binary>>) do
    {:ok, name, _rest} = BinaryUtils.parse_string(rest)
    %__MODULE__{npc_guid: guid, name: name}
  end
end

defmodule ThistleTea.Game.Network.Message.CmsgPetitionShowSignatures do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_PETITION_SHOW_SIGNATURES

  alias ThistleTea.Game.Player.Petitions

  defstruct [:item_guid]

  @impl ClientMessage
  def handle(%__MODULE__{item_guid: guid}, state), do: Petitions.show_signatures(state, guid)

  @impl ClientMessage
  def from_binary(<<guid::little-size(64), _rest::binary>>), do: %__MODULE__{item_guid: guid}
end

defmodule ThistleTea.Game.Network.Message.CmsgPetitionQuery do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_PETITION_QUERY

  alias ThistleTea.Game.Player.Petitions

  defstruct [:petition_id, :item_guid]

  @impl ClientMessage
  def handle(%__MODULE__{petition_id: id, item_guid: guid}, state), do: Petitions.query(state, id, guid)

  @impl ClientMessage
  def from_binary(<<id::little-size(32), guid::little-size(64), _rest::binary>>),
    do: %__MODULE__{petition_id: id, item_guid: guid}
end

defmodule ThistleTea.Game.Network.Message.CmsgOfferPetition do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_OFFER_PETITION

  alias ThistleTea.Game.Player.Petitions

  defstruct [:item_guid, :target_guid]

  @impl ClientMessage
  def handle(%__MODULE__{item_guid: item_guid, target_guid: target_guid}, state),
    do: Petitions.offer(state, item_guid, target_guid)

  @impl ClientMessage
  def from_binary(<<item_guid::little-size(64), target_guid::little-size(64), _rest::binary>>),
    do: %__MODULE__{item_guid: item_guid, target_guid: target_guid}
end

defmodule ThistleTea.Game.Network.Message.CmsgPetitionSign do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_PETITION_SIGN

  alias ThistleTea.Game.Player.Petitions

  defstruct [:item_guid]

  @impl ClientMessage
  def handle(%__MODULE__{item_guid: guid}, state), do: Petitions.sign(state, guid)

  @impl ClientMessage
  def from_binary(<<guid::little-size(64), _unknown::8, _rest::binary>>), do: %__MODULE__{item_guid: guid}
end

defmodule ThistleTea.Game.Network.Message.CmsgTurnInPetition do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_TURN_IN_PETITION

  alias ThistleTea.Game.Player.Petitions

  defstruct [:item_guid]

  @impl ClientMessage
  def handle(%__MODULE__{item_guid: guid}, state), do: Petitions.turn_in(state, guid)

  @impl ClientMessage
  def from_binary(<<guid::little-size(64), _rest::binary>>), do: %__MODULE__{item_guid: guid}
end

defmodule ThistleTea.Game.Network.Message.MsgPetitionDeclineClient do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :MSG_PETITION_DECLINE

  alias ThistleTea.Game.Player.Petitions

  defstruct [:item_guid]

  @impl ClientMessage
  def handle(%__MODULE__{item_guid: guid}, state), do: Petitions.decline(state, guid)

  @impl ClientMessage
  def from_binary(<<guid::little-size(64), _rest::binary>>), do: %__MODULE__{item_guid: guid}
end

defmodule ThistleTea.Game.Network.Message.MsgPetitionRenameClient do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :MSG_PETITION_RENAME

  alias ThistleTea.Game.Player.Petitions

  defstruct [:item_guid, :name]

  @impl ClientMessage
  def handle(%__MODULE__{item_guid: guid, name: name}, state), do: Petitions.rename(state, guid, name)

  @impl ClientMessage
  def from_binary(<<guid::little-size(64), rest::binary>>) do
    {:ok, name, _rest} = BinaryUtils.parse_string(rest)
    %__MODULE__{item_guid: guid, name: name}
  end
end
