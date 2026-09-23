defmodule ThistleTea.Game.Network.Message.CmsgGuildPromote do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GUILD_PROMOTE

  alias ThistleTea.Game.Player.Guilds

  defstruct [:name]

  @impl ClientMessage
  def handle(%__MODULE__{name: name}, state), do: Guilds.promote(state, name)

  @impl ClientMessage
  def from_binary(payload) do
    {:ok, name, _rest} = BinaryUtils.parse_string(payload)
    %__MODULE__{name: name}
  end
end

defmodule ThistleTea.Game.Network.Message.CmsgGuildDemote do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GUILD_DEMOTE

  alias ThistleTea.Game.Player.Guilds

  defstruct [:name]

  @impl ClientMessage
  def handle(%__MODULE__{name: name}, state), do: Guilds.demote(state, name)

  @impl ClientMessage
  def from_binary(payload) do
    {:ok, name, _rest} = BinaryUtils.parse_string(payload)
    %__MODULE__{name: name}
  end
end

defmodule ThistleTea.Game.Network.Message.CmsgGuildRemove do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GUILD_REMOVE

  alias ThistleTea.Game.Player.Guilds

  defstruct [:name]

  @impl ClientMessage
  def handle(%__MODULE__{name: name}, state), do: Guilds.remove(state, name)

  @impl ClientMessage
  def from_binary(payload) do
    {:ok, name, _rest} = BinaryUtils.parse_string(payload)
    %__MODULE__{name: name}
  end
end

defmodule ThistleTea.Game.Network.Message.CmsgGuildLeader do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GUILD_LEADER

  alias ThistleTea.Game.Player.Guilds

  defstruct [:name]

  @impl ClientMessage
  def handle(%__MODULE__{name: name}, state), do: Guilds.set_leader(state, name)

  @impl ClientMessage
  def from_binary(payload) do
    {:ok, name, _rest} = BinaryUtils.parse_string(payload)
    %__MODULE__{name: name}
  end
end

defmodule ThistleTea.Game.Network.Message.CmsgGuildMotd do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GUILD_MOTD

  alias ThistleTea.Game.Player.Guilds

  defstruct [:motd]

  @impl ClientMessage
  def handle(%__MODULE__{motd: motd}, state), do: Guilds.set_motd(state, motd)

  @impl ClientMessage
  def from_binary(payload) do
    {:ok, motd, _rest} = BinaryUtils.parse_string(payload)
    %__MODULE__{motd: motd}
  end
end

defmodule ThistleTea.Game.Network.Message.CmsgGuildInfoText do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GUILD_INFO_TEXT

  alias ThistleTea.Game.Player.Guilds

  defstruct [:info]

  @impl ClientMessage
  def handle(%__MODULE__{info: info}, state), do: Guilds.set_info(state, info)

  @impl ClientMessage
  def from_binary(payload) do
    {:ok, info, _rest} = BinaryUtils.parse_string(payload)
    %__MODULE__{info: info}
  end
end

defmodule ThistleTea.Game.Network.Message.CmsgGuildSetPublicNote do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GUILD_SET_PUBLIC_NOTE

  alias ThistleTea.Game.Player.Guilds

  defstruct [:name, :note]

  @impl ClientMessage
  def handle(%__MODULE__{name: name, note: note}, state), do: Guilds.set_note(state, name, :public_note, note)

  @impl ClientMessage
  def from_binary(payload) do
    {:ok, name, rest} = BinaryUtils.parse_string(payload)
    {:ok, note, _rest} = BinaryUtils.parse_string(rest)
    %__MODULE__{name: name, note: note}
  end
end

defmodule ThistleTea.Game.Network.Message.CmsgGuildSetOfficerNote do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GUILD_SET_OFFICER_NOTE

  alias ThistleTea.Game.Player.Guilds

  defstruct [:name, :note]

  @impl ClientMessage
  def handle(%__MODULE__{name: name, note: note}, state), do: Guilds.set_note(state, name, :officer_note, note)

  @impl ClientMessage
  def from_binary(payload) do
    {:ok, name, rest} = BinaryUtils.parse_string(payload)
    {:ok, note, _rest} = BinaryUtils.parse_string(rest)
    %__MODULE__{name: name, note: note}
  end
end

defmodule ThistleTea.Game.Network.Message.CmsgGuildInfo do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GUILD_INFO

  alias ThistleTea.Game.Player.Guilds

  defstruct []

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Guilds.info(state)

  @impl ClientMessage
  def from_binary(_payload), do: %__MODULE__{}
end

defmodule ThistleTea.Game.Network.Message.CmsgGuildRank do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GUILD_RANK

  alias ThistleTea.Game.Player.Guilds

  defstruct [:rank_id, :rights, :name]

  @impl ClientMessage
  def handle(%__MODULE__{rank_id: rank_id, rights: rights, name: name}, state),
    do: Guilds.edit_rank(state, rank_id, rights, name)

  @impl ClientMessage
  def from_binary(<<rank_id::little-size(32), rights::little-size(32), payload::binary>>) do
    {:ok, name, _rest} = BinaryUtils.parse_string(payload)
    %__MODULE__{rank_id: rank_id, rights: rights, name: name}
  end
end

defmodule ThistleTea.Game.Network.Message.CmsgGuildAddRank do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GUILD_ADD_RANK

  alias ThistleTea.Game.Player.Guilds

  defstruct [:name]

  @impl ClientMessage
  def handle(%__MODULE__{name: name}, state), do: Guilds.add_rank(state, name)

  @impl ClientMessage
  def from_binary(payload) do
    {:ok, name, _rest} = BinaryUtils.parse_string(payload)
    %__MODULE__{name: name}
  end
end

defmodule ThistleTea.Game.Network.Message.CmsgGuildDelRank do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GUILD_DEL_RANK

  alias ThistleTea.Game.Player.Guilds

  defstruct []

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Guilds.delete_rank(state)

  @impl ClientMessage
  def from_binary(_payload), do: %__MODULE__{}
end
