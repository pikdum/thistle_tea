defmodule ThistleTea.Game.World.Loader.PetSpells do
  @moduledoc """
  Cached spell ranks, training costs, and discoverable recipes of tameable beasts.
  Creature spell data takes precedence over the VMangos creation-spell fallback.
  """

  import Ecto.Query

  alias ThistleTea.DB.Mangos
  alias ThistleTea.DBC
  alias ThistleTea.Game.Entity.Data.PetAbility
  alias ThistleTea.Game.World.Loader.PetTraining
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, [:named_table, :public, read_concurrency: true])
      _ -> table
    end
  end

  def load_all(table \\ __MODULE__) do
    abilities = PetTraining.abilities()
    ability_ids = Map.keys(abilities)

    teaching =
      DBC.all(
        from(spell in Spell,
          where: spell.effect_0 in [36, 57] and spell.effect_trigger_spell_0 in ^ability_ids,
          select: {spell.id, spell.effect_trigger_spell_0}
        )
      )
      |> Map.new()

    creatures =
      Mangos.Repo.all(
        from(creature in Mangos.CreatureTemplate,
          where: fragment("(? & 16) != 0", creature.creature_type_flags),
          select: {creature.entry, creature.pet_spell_data_id}
        )
      )

    fallback = Map.new(Mangos.Repo.all(Mangos.PetCreateInfoSpell), &{&1.entry, Mangos.PetCreateInfoSpell.spell_ids(&1)})
    dbc = Map.new(DBC.all(CreatureSpellData), &{&1.id, CreatureSpellData.spell_ids(&1)})

    sources =
      Map.new(creatures, fn {entry, data_id} -> {entry, Map.get(dbc, data_id, Map.get(fallback, entry, []))} end)

    spells =
      sources
      |> Map.values()
      |> List.flatten()
      |> Enum.map(&Map.get(teaching, &1, &1))
      |> Enum.uniq()
      |> SpellLoader.build_spellbook()

    profiles = Enum.map(sources, fn {entry, ids} -> {{:profile, entry}, build(ids, spells, teaching, abilities)} end)
    :ets.insert(table, profiles)
    :ok
  end

  def build(ids, spells, teaching, abilities) do
    recipes = teaching |> Enum.sort() |> Map.new(fn {recipe, ability} -> {ability, recipe} end)
    spellbook = Map.take(spells, Enum.map(ids, &Map.get(teaching, &1, &1)))

    recipes =
      Map.new(ids, fn id ->
        ability = Map.get(teaching, id, id)
        {ability, if(Map.has_key?(teaching, id), do: id, else: Map.get(recipes, ability))}
      end)
      |> Map.take(Map.keys(spellbook))
      |> Map.reject(fn {_ability, recipe} -> is_nil(recipe) end)

    cost =
      Enum.reduce(Map.keys(spellbook), 0, fn id, total ->
        case Map.get(abilities, id) do
          %PetAbility{cost: cost} -> total + cost
          _ -> total
        end
      end)

    %{spellbook: spellbook, recipes: recipes, training_points: -cost}
  end

  def profile(entry, table \\ __MODULE__) do
    case :ets.lookup(table, {:profile, entry}) do
      [{_key, profile}] -> profile
      _ -> empty()
    end
  end

  defp empty, do: %{spellbook: %{}, recipes: %{}, training_points: 0}
end
