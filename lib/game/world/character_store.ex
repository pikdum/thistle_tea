defmodule ThistleTea.Game.World.CharacterStore do
  @moduledoc """
  ETS store of characters by id, mirroring `ItemStore` — in-memory only;
  durable persistence is deferred until the runtime model settles.
  """
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Guid

  @table_options [:named_table, :public, read_concurrency: true, write_concurrency: :auto]

  def init(table \\ __MODULE__) do
    table =
      case :ets.whereis(table) do
        :undefined -> :ets.new(table, @table_options)
        _table_id -> table
      end

    :ets.insert_new(table, {:counter, 0})
    table
  end

  def create(%Character{} = character) do
    id = next_id()
    guid = Guid.from_low_guid(:player, id)

    %{character | id: id, object: %{character.object | guid: guid}}
    |> put()
  end

  def put(%Character{id: id} = character) when is_integer(id) and id > 0 do
    :ets.insert(__MODULE__, {id, character})
    character
  end

  def get(id) when is_integer(id) and id > 0 do
    case :ets.lookup(__MODULE__, id) do
      [{^id, %Character{} = character}] -> character
      _ -> nil
    end
  end

  def get(_id), do: nil

  def fetch(account_id, id) do
    case get(id) do
      %Character{account_id: ^account_id} = character -> {:ok, character}
      _ -> {:error, :character_not_found}
    end
  end

  def get_by_name(name) when is_binary(name) do
    Enum.find(all(), fn %Character{internal: internal} -> internal.name == name end)
  end

  def for_account(account_id) do
    Enum.filter(all(), &(&1.account_id == account_id))
  end

  def all do
    __MODULE__
    |> :ets.tab2list()
    |> Enum.flat_map(fn
      {id, %Character{} = character} when is_integer(id) -> [character]
      _ -> []
    end)
    |> Enum.sort_by(& &1.id)
  end

  defp next_id do
    :ets.update_counter(__MODULE__, :counter, 1)
  end
end
