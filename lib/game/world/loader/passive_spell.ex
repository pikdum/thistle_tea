defmodule ThistleTea.Game.World.Loader.PassiveSpell do
  @moduledoc "Preloads hidden learned-spell dependencies from the vanilla seed data."

  import Ecto.Query

  alias ThistleTea.DB.Mangos

  @client_build 5875
  @table_options [:named_table, :public, read_concurrency: true, write_concurrency: :auto]

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
  end

  def load_all do
    from(link in "spell_learn_spell",
      where: link.build_min <= @client_build and link.build_max >= @client_build and field(link, :Active) == 0,
      select: {link.entry, field(link, :SpellID)}
    )
    |> Mangos.Repo.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.each(fn {id, children} -> :ets.insert(__MODULE__, {id, Enum.sort(children)}) end)

    :ok
  end

  def get(spell_id) do
    case :ets.lookup(__MODULE__, spell_id) do
      [{^spell_id, children}] -> children
      _missing -> []
    end
  rescue
    ArgumentError -> []
  end
end
