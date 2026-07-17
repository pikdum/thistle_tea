defmodule ThistleTea.Game.World.Loader.SpellScript do
  @moduledoc """
  Preloads VMangos `spell_scripts` commands into ETS so DBC spells carry
  their database-defined script steps into the pure spell-effect core.
  """
  import Ecto.Query

  alias ThistleTea.DB.Mangos
  alias ThistleTea.DB.Mangos.SpellScript
  alias ThistleTea.Game.World.Loader.Script

  @table_options [:named_table, :public, read_concurrency: true, write_concurrency: :auto]

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
  end

  def load_all do
    script_ids = Mangos.Repo.all(from(s in SpellScript, distinct: true, select: s.id))

    SpellScript
    |> Script.load_by_ids(script_ids)
    |> Enum.each(fn {spell_id, steps} -> :ets.insert(__MODULE__, {spell_id, steps}) end)

    :ok
  end

  def get(spell_id) when is_integer(spell_id) and spell_id > 0 do
    case :ets.lookup(__MODULE__, spell_id) do
      [{^spell_id, steps}] -> steps
      _ -> []
    end
  rescue
    ArgumentError -> []
  end

  def get(_spell_id), do: []
end
