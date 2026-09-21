defmodule ThistleTea.Game.World.SocialStore do
  @moduledoc """
  Runtime social lists. The character's player owner writes its entire row
  atomically; readers can inspect relationships while that character is offline.
  """

  alias ThistleTea.Game.Social

  @table_options [:named_table, :public, read_concurrency: true, write_concurrency: :auto]

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
  end

  def get(guid, table \\ __MODULE__) do
    case :ets.lookup(table, guid) do
      [{^guid, %Social{} = social}] -> social
      [] -> %Social{owner_guid: guid}
    end
  end

  def put(%Social{owner_guid: guid} = social, table \\ __MODULE__) when is_integer(guid) and guid > 0 do
    :ets.insert(table, {guid, social})
    social
  end

  def ignores?(owner_guid, target_guid, table \\ __MODULE__) do
    owner_guid |> get(table) |> Social.member?(:ignore, target_guid)
  end

  def followers(guid, table \\ __MODULE__) do
    :ets.foldl(
      fn {owner, %Social{} = social}, owners ->
        if Social.member?(social, :friend, guid), do: [owner | owners], else: owners
      end,
      [],
      table
    )
    |> Enum.sort()
  end
end
