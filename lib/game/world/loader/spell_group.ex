defmodule ThistleTea.Game.World.Loader.SpellGroup do
  @moduledoc "Preloads explicit spell stacking groups for the supported client build."
  import Ecto.Query

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Core.Spell.StackRules

  @client_build 5875
  @table_options [:named_table, :public, read_concurrency: true, write_concurrency: :auto]

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
  end

  def load_all do
    members =
      Mangos.Repo.all(
        from(row in "spell_group",
          select: map(row, [:group_id, :group_spell_id, :spell_id, :build_min, :build_max])
        )
      )

    rules =
      Mangos.Repo.all(from(row in "spell_group_stack_rules", select: map(row, [:group_id, :build, :stack_rule])))

    entries = StackRules.compile(members, rules, @client_build)
    :ets.delete_all_objects(__MODULE__)
    :ets.insert(__MODULE__, Map.to_list(entries))
    :ok
  end

  def get(spell_id) do
    case :ets.lookup(__MODULE__, spell_id) do
      [{^spell_id, rules}] -> rules
      _missing -> %StackRules{}
    end
  rescue
    ArgumentError -> %StackRules{}
  end

  def get(spell_id, first_spell), do: StackRules.inherit(get(spell_id), get(first_spell))
end
