defmodule ThistleTea.Game.Network.Message.SmsgGuildRoster do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_GUILD_ROSTER

  alias ThistleTea.Game.Guild.Group

  defmodule Entry do
    @moduledoc false
    @enforce_keys [:guid, :name, :rank, :level, :class, :area, :online?]
    defstruct [:guid, :name, :rank, :level, :class, :area, :online?, :offline_days, public_note: "", officer_note: ""]
  end

  defstruct [:guild, entries: []]

  @impl ServerMessage
  def to_binary(%__MODULE__{guild: %Group{} = guild, entries: entries}) do
    rights = IO.iodata_to_binary(Enum.map(guild.ranks, &<<&1.rights::little-size(32)>>))
    members = IO.iodata_to_binary(Enum.map(entries, &encode_entry/1))

    <<length(entries)::little-size(32)>> <>
      guild.motd <>
      <<0>> <>
      guild.info <>
      <<0>> <>
      <<length(guild.ranks)::little-size(32)>> <> rights <> members
  end

  defp encode_entry(%Entry{} = entry) do
    status = if(entry.online?, do: 1, else: 0)
    offline = if(entry.online?, do: <<>>, else: <<entry.offline_days || 0.0::little-float-size(32)>>)

    <<entry.guid::little-size(64), status::8>> <>
      entry.name <>
      <<0, entry.rank::little-size(32), entry.level::8, entry.class::8, entry.area::little-size(32)>> <>
      offline <>
      entry.public_note <> <<0>> <> entry.officer_note <> <<0>>
  end
end
