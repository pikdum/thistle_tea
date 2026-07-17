defmodule ThistleTea.Game.World.Loader.SpellProcEvent do
  @moduledoc """
  Preloads the VMangos proc restrictions for the supported client build.
  """
  import Bitwise, only: [>>>: 2, &&&: 2]
  import Ecto.Query

  alias ThistleTea.DB.Mangos
  alias ThistleTea.DB.Mangos.SpellProcEvent
  alias ThistleTea.Game.Spell.ProcRule

  @client_build 5875
  @table_options [:named_table, :public, read_concurrency: true, write_concurrency: :auto]

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
  end

  def load_all do
    SpellProcEvent
    |> where([rule], rule.build_min <= @client_build and rule.build_max >= @client_build)
    |> Mangos.Repo.all()
    |> Enum.each(&:ets.insert(__MODULE__, {&1.entry, build(&1)}))

    :ok
  end

  def get(spell_id) when is_integer(spell_id) and spell_id > 0 do
    case :ets.lookup(__MODULE__, spell_id) do
      [{^spell_id, %ProcRule{} = rule}] -> rule
      _missing -> nil
    end
  rescue
    ArgumentError -> nil
  end

  def get(_spell_id), do: nil

  defp build(%SpellProcEvent{} = rule) do
    family_mask = rule.family_mask_0 || 0

    %ProcRule{
      school_mask: rule.school_mask || 0,
      spell_family: rule.spell_family || 0,
      family_mask_0: family_mask &&& 0xFFFFFFFF,
      family_mask_1: family_mask >>> 32,
      proc_flags: rule.proc_flags || 0,
      proc_ex: rule.proc_ex || 0,
      ppm_rate: rule.ppm_rate || 0.0,
      custom_chance: rule.custom_chance || 0.0,
      cooldown_ms: rule.cooldown_ms || 0
    }
  end
end
