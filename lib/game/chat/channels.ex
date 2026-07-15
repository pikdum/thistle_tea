defmodule ThistleTea.Game.Chat.Channels do
  @moduledoc """
  Pure directory of active chat channels with a reverse membership index.
  """
  alias ThistleTea.Game.Chat.Channel
  alias ThistleTea.Game.Chat.Channel.Member

  defstruct channels: %{}, memberships: %{}

  def join(%__MODULE__{} = channels, %Member{} = actor, name, password, definition) do
    key = key(actor.team, name)
    channel = Map.get_lazy(channels.channels, key, fn -> Channel.new(key, name, actor.team, definition) end)

    with {:ok, channel, outcome} <- Channel.join(channel, actor, password) do
      channels =
        channels
        |> put(channel)
        |> add_membership(actor.guid, key)

      {:ok, channel, outcome, channels}
    end
  end

  def leave(%__MODULE__{} = channels, %Member{} = actor, name) do
    with {:ok, channel} <- fetch(channels, actor, name),
         {:ok, channel, outcome} <- Channel.leave(channel, actor.guid) do
      channels =
        channels
        |> put(channel)
        |> remove_membership(actor.guid, channel.key)

      {:ok, channel, outcome, channels}
    end
  end

  def leave_all(%__MODULE__{} = channels, guid) do
    keys = channels.memberships |> Map.get(guid, MapSet.new()) |> MapSet.to_list()

    Enum.reduce(keys, {[], channels}, fn key, {outcomes, channels} ->
      channel = Map.fetch!(channels.channels, key)

      case Channel.leave(channel, guid) do
        {:ok, channel, outcome} ->
          channels =
            channels
            |> put(channel)
            |> remove_membership(guid, key)

          {[{channel, outcome} | outcomes], channels}

        {:error, :not_member} ->
          {outcomes, remove_membership(channels, guid, key)}
      end
    end)
  end

  def fetch(%__MODULE__{} = channels, %Member{} = actor, name) do
    case Map.fetch(channels.channels, key(actor.team, name)) do
      {:ok, channel} -> {:ok, channel}
      :error -> {:error, :not_member}
    end
  end

  def put(%__MODULE__{} = channels, %Channel{members: members} = channel) when map_size(members) == 0 do
    %{channels | channels: Map.delete(channels.channels, channel.key)}
  end

  def put(%__MODULE__{} = channels, %Channel{} = channel) do
    %{channels | channels: Map.put(channels.channels, channel.key, channel)}
  end

  def remove_member(%__MODULE__{} = channels, %Channel{} = channel, guid) do
    channels
    |> put(channel)
    |> remove_membership(guid, channel.key)
  end

  def key(team, name), do: {team, normalize(name)}

  defp add_membership(channels, guid, key) do
    memberships = Map.update(channels.memberships, guid, MapSet.new([key]), &MapSet.put(&1, key))
    %{channels | memberships: memberships}
  end

  defp remove_membership(channels, guid, key) do
    memberships =
      case Map.get(channels.memberships, guid) do
        nil ->
          channels.memberships

        keys ->
          keys = MapSet.delete(keys, key)

          if MapSet.size(keys) == 0,
            do: Map.delete(channels.memberships, guid),
            else: Map.put(channels.memberships, guid, keys)
      end

    %{channels | memberships: memberships}
  end

  defp normalize(value), do: value |> String.trim() |> String.downcase()
end
