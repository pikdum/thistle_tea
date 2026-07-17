defmodule ThistleTea.Game.World.Loader.ItemEnchantment do
  @moduledoc """
  Preloaded item-enchantment definitions and VMangos temporary-duration overrides.
  """
  import Ecto.Query

  alias ThistleTea.DB.Mangos
  alias ThistleTea.DBC
  alias ThistleTea.Game.Entity.Data.ItemEnchantment
  alias ThistleTea.Game.Spell.Effect

  @equip_spell_type 3
  @mod_skill_aura 30
  @table_options [:named_table, :public, read_concurrency: true]

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
  end

  def load_all do
    rows = DBC.all(SpellItemEnchantment)
    equip_spell_ids = rows |> Enum.flat_map(&equip_spell_ids/1) |> Enum.uniq()
    skill_bonuses = load_skill_bonuses(equip_spell_ids)

    Enum.each(rows, fn row ->
      enchantment = build(row, skill_bonuses)
      :ets.insert(__MODULE__, {{:enchantment, row.id}, enchantment})
    end)

    Mangos.Repo.all(Mangos.SpellEffectMod)
    |> Enum.each(&:ets.insert(__MODULE__, {{:duration_seconds, &1.id}, &1.effect_base_points + 1}))

    Mangos.Repo.all(Mangos.SpellProcItemEnchant)
    |> Enum.each(&:ets.insert(__MODULE__, {{:proc_ppm, &1.entry}, &1.ppm_rate}))

    :ok
  end

  def get(enchantment_id) when is_integer(enchantment_id) do
    case :ets.lookup(__MODULE__, {:enchantment, enchantment_id}) do
      [{_key, %ItemEnchantment{} = enchantment}] -> enchantment
      [] -> nil
    end
  end

  def duration_ms(spell_id, %Effect{} = effect) do
    seconds =
      case :ets.lookup(__MODULE__, {:duration_seconds, spell_id}) do
        [{_key, seconds}] -> seconds
        [] -> Effect.damage_roll(effect)
      end

    max(seconds, 1) * 1_000
  end

  def skill_bonus(enchantment_id, skill_id) do
    case get(enchantment_id) do
      %ItemEnchantment{skill_bonuses: bonuses} -> Map.get(bonuses, skill_id, 0)
      nil -> 0
    end
  end

  def proc_ppm(spell_id) when is_integer(spell_id) do
    case :ets.lookup(__MODULE__, {:proc_ppm, spell_id}) do
      [{_key, ppm}] -> ppm
      [] -> 0.0
    end
  end

  defp build(row, skill_bonuses) do
    effects =
      Enum.map(0..2, fn index ->
        %{
          type: Map.get(row, :"enchantment_type_#{index}"),
          amount: Map.get(row, :"effect_points_min_#{index}"),
          spell_id: Map.get(row, :"effect_arg_#{index}")
        }
      end)
      |> Enum.reject(&(&1.type == 0))

    bonuses =
      effects
      |> Enum.map(& &1.spell_id)
      |> Enum.reduce(%{}, fn spell_id, acc -> Map.merge(acc, Map.get(skill_bonuses, spell_id, %{})) end)

    %ItemEnchantment{
      id: row.id,
      name: row.name_en_gb,
      item_visual: row.item_visual,
      flags: row.flags,
      effects: effects,
      skill_bonuses: bonuses
    }
  end

  defp equip_spell_ids(row) do
    Enum.flat_map(0..2, fn index ->
      if Map.get(row, :"enchantment_type_#{index}") == @equip_spell_type do
        [Map.get(row, :"effect_arg_#{index}")]
      else
        []
      end
    end)
  end

  defp load_skill_bonuses([]), do: %{}

  defp load_skill_bonuses(spell_ids) do
    DBC.all(
      from(s in Elixir.Spell,
        where: s.id in ^spell_ids,
        select: %{
          id: s.id,
          effects: [
            {s.effect_0, s.effect_aura_0, s.effect_misc_value_0, s.effect_base_points_0, s.effect_die_sides_0},
            {s.effect_1, s.effect_aura_1, s.effect_misc_value_1, s.effect_base_points_1, s.effect_die_sides_1},
            {s.effect_2, s.effect_aura_2, s.effect_misc_value_2, s.effect_base_points_2, s.effect_die_sides_2}
          ]
        }
      )
    )
    |> Map.new(fn row ->
      bonuses =
        row.effects
        |> Enum.flat_map(fn
          {6, @mod_skill_aura, skill_id, base, sides} -> [{skill_id, base + max(sides, 1)}]
          _ -> []
        end)
        |> Map.new()

      {row.id, bonuses}
    end)
  end
end
