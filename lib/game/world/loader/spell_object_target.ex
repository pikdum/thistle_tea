defmodule ThistleTea.Game.World.Loader.SpellObjectTarget do
  @moduledoc "Preloads object selectors and their conditions from VMangos spell_script_target."

  import Ecto.Query

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Spell.ObjectTargets.Selector
  alias ThistleTea.Game.World.Loader.Condition

  def init do
    case :ets.whereis(__MODULE__) do
      :undefined -> :ets.new(__MODULE__, [:named_table, :public, read_concurrency: true])
      table -> table
    end
  end

  def load_all do
    rows =
      Mangos.Repo.all(
        from(s in Mangos.SpellScriptTarget, where: s.type == 0 and s.build_min <= 5875 and s.build_max >= 5875)
      )

    conditions = rows |> Enum.map(& &1.condition_id) |> Condition.load_by_ids()

    rows
    |> Enum.group_by(& &1.entry, &build(&1, conditions))
    |> Enum.each(&:ets.insert(__MODULE__, &1))

    :ok
  end

  def build(%Mangos.SpellScriptTarget{} = row, conditions) do
    %Selector{
      entry: row.target_entry,
      condition: Map.get(conditions, row.condition_id),
      inverse_effect_mask: row.inverse_effect_mask
    }
  end

  def get(spell_id) do
    case :ets.lookup(__MODULE__, spell_id) do
      [{^spell_id, targets}] -> targets
      _ -> []
    end
  rescue
    ArgumentError -> []
  end
end
