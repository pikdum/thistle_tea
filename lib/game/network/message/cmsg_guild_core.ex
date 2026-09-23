defmodule ThistleTea.Game.Network.Message.CmsgGuildQuery do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GUILD_QUERY

  alias ThistleTea.Game.Player.Guilds

  defstruct [:guild_id]

  @impl ClientMessage
  def handle(%__MODULE__{guild_id: id}, state), do: Guilds.query(state, id)

  @impl ClientMessage
  def from_binary(<<guild_id::little-size(32), _rest::binary>>), do: %__MODULE__{guild_id: guild_id}
end

defmodule ThistleTea.Game.Network.Message.CmsgGuildCreate do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GUILD_CREATE

  alias ThistleTea.Game.Player.Guilds

  defstruct [:name]

  @impl ClientMessage
  def handle(%__MODULE__{name: name}, state), do: Guilds.create(state, name)

  @impl ClientMessage
  def from_binary(payload) do
    {:ok, name, _rest} = BinaryUtils.parse_string(payload)
    %__MODULE__{name: name}
  end
end

defmodule ThistleTea.Game.Network.Message.CmsgGuildInvite do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GUILD_INVITE

  alias ThistleTea.Game.Player.Guilds

  defstruct [:name]

  @impl ClientMessage
  def handle(%__MODULE__{name: name}, state), do: Guilds.invite(state, name)

  @impl ClientMessage
  def from_binary(payload) do
    {:ok, name, _rest} = BinaryUtils.parse_string(payload)
    %__MODULE__{name: name}
  end
end

defmodule ThistleTea.Game.Network.Message.CmsgGuildAccept do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GUILD_ACCEPT

  alias ThistleTea.Game.Player.Guilds

  defstruct []

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Guilds.accept(state)

  @impl ClientMessage
  def from_binary(_payload), do: %__MODULE__{}
end

defmodule ThistleTea.Game.Network.Message.CmsgGuildDecline do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GUILD_DECLINE

  alias ThistleTea.Game.Player.Guilds

  defstruct []

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Guilds.decline(state)

  @impl ClientMessage
  def from_binary(_payload), do: %__MODULE__{}
end

defmodule ThistleTea.Game.Network.Message.CmsgGuildRoster do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GUILD_ROSTER

  alias ThistleTea.Game.Player.Guilds

  defstruct []

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Guilds.roster(state)

  @impl ClientMessage
  def from_binary(_payload), do: %__MODULE__{}
end

defmodule ThistleTea.Game.Network.Message.CmsgGuildLeave do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GUILD_LEAVE

  alias ThistleTea.Game.Player.Guilds

  defstruct []

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Guilds.leave(state)

  @impl ClientMessage
  def from_binary(_payload), do: %__MODULE__{}
end

defmodule ThistleTea.Game.Network.Message.CmsgGuildDisband do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GUILD_DISBAND

  alias ThistleTea.Game.Player.Guilds

  defstruct []

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Guilds.disband(state)

  @impl ClientMessage
  def from_binary(_payload), do: %__MODULE__{}
end
