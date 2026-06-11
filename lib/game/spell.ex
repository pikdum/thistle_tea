defmodule ThistleTea.Game.Spell do
  import Bitwise, only: [<<<: 2]

  alias ThistleTea.Game.Spell.Effect

  defstruct [
    :id,
    :name,
    :school,
    :cast_time_ms,
    :duration_ms,
    :range_yards,
    :mana_cost,
    :power_type,
    :gcd_ms,
    :dispel_type,
    :first_in_chain,
    :rank,
    :exclusive_category,
    speed: 0.0,
    aura_interrupt_flags: 0,
    attributes: MapSet.new(),
    effects: [],
    reagents: []
  ]

  def attribute?(%__MODULE__{attributes: attrs}, attr), do: MapSet.member?(attrs, attr)

  def same_chain?(%__MODULE__{id: id1, first_in_chain: first1}, %__MODULE__{id: id2, first_in_chain: first2}) do
    id1 != id2 and is_integer(first1) and first1 == first2
  end

  def stronger_rank_of_same_chain?(%__MODULE__{rank: rank1} = spell1, %__MODULE__{rank: rank2} = spell2) do
    same_chain?(spell1, spell2) and is_integer(rank1) and is_integer(rank2) and rank1 > rank2
  end

  def same_exclusive_category?(%__MODULE__{id: id1, exclusive_category: cat1}, %__MODULE__{
        id: id2,
        exclusive_category: cat2
      }) do
    id1 != id2 and not is_nil(cat1) and cat1 == cat2
  end

  def school_mask(%__MODULE__{school: school}), do: school_mask(school)
  def school_mask(:physical), do: school_mask_index(0)
  def school_mask(:holy), do: school_mask_index(1)
  def school_mask(:fire), do: school_mask_index(2)
  def school_mask(:nature), do: school_mask_index(3)
  def school_mask(:frost), do: school_mask_index(4)
  def school_mask(:shadow), do: school_mask_index(5)
  def school_mask(:arcane), do: school_mask_index(6)
  def school_mask(school) when is_integer(school), do: school_mask_index(school)
  def school_mask(_school), do: 0

  def school_index(%__MODULE__{school: school}), do: school_index(school)
  def school_index(:physical), do: 0
  def school_index(:holy), do: 1
  def school_index(:fire), do: 2
  def school_index(:nature), do: 3
  def school_index(:frost), do: 4
  def school_index(:shadow), do: 5
  def school_index(:arcane), do: 6
  def school_index(school) when is_integer(school), do: school
  def school_index(_school), do: 0

  defp school_mask_index(school) when is_integer(school) and school >= 0, do: 1 <<< school
  defp school_mask_index(_school), do: 0

  def aura_effects(%__MODULE__{effects: effects}) do
    Enum.filter(effects, &match?(%Effect{type: :apply_aura}, &1))
  end

  def damage_effects(%__MODULE__{effects: effects}) do
    Enum.filter(
      effects,
      &match?(%Effect{type: type} when type in [:school_damage, :weapon_damage, :weapon_damage_noschool], &1)
    )
  end

  def channel_tick_ms(%__MODULE__{effects: effects}) do
    effects
    |> Enum.map(& &1.amplitude_ms)
    |> Enum.filter(&(is_integer(&1) and &1 > 0))
    |> Enum.min(fn -> 1_000 end)
  end
end
