defmodule ThistleTea.Game.World.Loader.SpellEffectOverride do
  @moduledoc """
  Preloads VMangos's per-effect spell fix data: `spell_effect_mod` field
  overrides and `spell_template` bonus coefficients for the supported
  client build, so the spell loader can correct DBC rows the way VMangos
  does instead of hardcoding the same fixes.
  """
  import Ecto.Query

  alias ThistleTea.DB.Mangos
  alias ThistleTea.DB.Mangos.SpellEffectMod
  alias ThistleTea.DB.Mangos.SpellTemplate

  @client_build 5875
  @table_options [:named_table, :public, read_concurrency: true, write_concurrency: :auto]

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
  end

  def load_all do
    load_effect_mods()
    load_bonus_coefficients()
    :ok
  end

  defp load_effect_mods do
    SpellEffectMod
    |> Mangos.Repo.all()
    |> Enum.group_by(& &1.id)
    |> Enum.each(fn {spell_id, rows} ->
      :ets.insert(__MODULE__, {{:mods, spell_id}, Map.new(rows, &{&1.effect_index, &1})})
    end)
  end

  defp load_bonus_coefficients do
    latest_builds =
      from(s in SpellTemplate,
        where: s.build <= @client_build,
        group_by: s.entry,
        select: %{entry: s.entry, build: max(s.build)}
      )

    SpellTemplate
    |> join(:inner, [s], latest in subquery(latest_builds), on: latest.entry == s.entry and latest.build == s.build)
    |> select(
      [s],
      {s.entry, {s.effect_bonus_coefficient_0, s.effect_bonus_coefficient_1, s.effect_bonus_coefficient_2}}
    )
    |> Mangos.Repo.all()
    |> Enum.each(fn {entry, coefficients} ->
      if coefficients != {-1.0, -1.0, -1.0} do
        :ets.insert(__MODULE__, {{:coefficients, entry}, coefficients})
      end
    end)
  end

  def mods(spell_id) when is_integer(spell_id) and spell_id > 0 do
    case :ets.lookup(__MODULE__, {:mods, spell_id}) do
      [{_key, mods}] -> mods
      _ -> %{}
    end
  rescue
    ArgumentError -> %{}
  end

  def mods(_spell_id), do: %{}

  def bonus_coefficient(spell_id, effect_index) when is_integer(spell_id) and spell_id > 0 and effect_index in 0..2 do
    case :ets.lookup(__MODULE__, {:coefficients, spell_id}) do
      [{_key, coefficients}] -> elem(coefficients, effect_index)
      _ -> nil
    end
  rescue
    ArgumentError -> nil
  end

  def bonus_coefficient(_spell_id, _effect_index), do: nil
end
