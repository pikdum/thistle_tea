defmodule ThistleTea.Game.World.Loader.ChatChannel do
  @moduledoc """
  Loads built-in chat-channel definitions from ChatChannels.dbc at startup.
  """
  import Bitwise

  alias ThistleTea.DBC

  @dbc_trade 0x00008
  @dbc_city 0x00020
  @dbc_lfg 0x40000

  @flag_trade 0x04
  @flag_not_lfg 0x08
  @flag_general 0x10
  @flag_city 0x20
  @flag_lfg 0x40

  def load do
    ChatChannels
    |> DBC.all()
    |> Enum.map(&definition/1)
  end

  def defaults do
    [
      %ChatChannels{id: 1, flags: 3, name: "General - %s"},
      %ChatChannels{id: 2, flags: 59, name: "Trade - %s"},
      %ChatChannels{id: 22, flags: 65_539, name: "LocalDefense - %s"},
      %ChatChannels{id: 23, flags: 65_540, name: "WorldDefense"},
      %ChatChannels{id: 24, flags: 0, name: "LookingForGroup"},
      %ChatChannels{id: 25, flags: 131_122, name: "GuildRecruitment - %s"}
    ]
    |> Enum.map(&definition/1)
  end

  def resolve(definitions, name) when is_binary(name) do
    Enum.find(definitions, &matches?(&1.pattern, name)) || %{kind: :custom, flags: 0x01, pattern: name}
  end

  defp definition(%ChatChannels{} = channel) do
    %{kind: {:builtin, channel.id}, flags: channel_flags(channel.flags), pattern: channel.name}
  end

  defp channel_flags(dbc_flags) do
    @flag_general
    |> add_if(dbc_flags, @dbc_trade, @flag_trade)
    |> add_if(dbc_flags, @dbc_city, @flag_city)
    |> add_lfg(dbc_flags)
  end

  defp add_lfg(flags, dbc_flags) when band(dbc_flags, @dbc_lfg) != 0, do: flags ||| @flag_lfg
  defp add_lfg(flags, _dbc_flags), do: flags ||| @flag_not_lfg

  defp add_if(flags, value, mask, flag) when band(value, mask) != 0, do: flags ||| flag
  defp add_if(flags, _value, _mask, _flag), do: flags

  defp matches?(pattern, name) do
    normalized_name = normalize(name)

    case String.split(normalize(pattern), "%s", parts: 2) do
      [exact] -> normalized_name == exact
      [prefix, suffix] -> String.starts_with?(normalized_name, prefix) and String.ends_with?(normalized_name, suffix)
    end
  end

  defp normalize(value), do: value |> String.trim() |> String.downcase()
end
