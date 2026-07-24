defmodule ThistleTea.Game.World.Loader.SpellPetAura do
  @moduledoc """
  Preloads the VMangos pet-aura links: owner spells (Soul Link, Spirit
  Bond, Master Demonologist, …) that place an aura on the active pet,
  keyed by owner spell id with a pet entry filter (0 matches any pet).
  """

  alias ThistleTea.DB.Mangos
  alias ThistleTea.DB.Mangos.SpellPetAura

  @table_options [:named_table, :public, read_concurrency: true, write_concurrency: :auto]

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
  end

  def load_all do
    SpellPetAura
    |> Mangos.Repo.all()
    |> Enum.group_by(& &1.spell, &{&1.pet, &1.aura})
    |> Enum.each(fn {spell_id, links} -> :ets.insert(__MODULE__, {spell_id, links}) end)

    :ok
  end

  def pet_aura_ids(spell_id, pet_entry) when is_integer(spell_id) and spell_id > 0 do
    case :ets.lookup(__MODULE__, spell_id) do
      [{^spell_id, links}] ->
        for {pet, aura} <- links, pet == 0 or pet == pet_entry, do: aura

      _missing ->
        []
    end
  rescue
    ArgumentError -> []
  end

  def pet_aura_ids(_spell_id, _pet_entry), do: []
end
