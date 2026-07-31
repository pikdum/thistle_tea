defmodule ThistleTea.Game.World.Loader.Reputation do
  @moduledoc """
  Loads DBC faction definitions and VMangos reputation rewards into an
  immutable internal catalog cached at the world boundary.
  """

  alias ThistleTea.DB.Mangos
  alias ThistleTea.DBC
  alias ThistleTea.Game.Entity.Data.Reputation.Catalog
  alias ThistleTea.Game.Entity.Data.Reputation.Definition
  alias ThistleTea.Game.Entity.Data.Reputation.KillReward
  alias ThistleTea.Game.Entity.Data.Reputation.Spillover
  alias ThistleTea.Game.Entity.Data.Reputation.Variant

  @table_options [:named_table, :public, read_concurrency: true]
  @no_reputation_index 4_294_967_295

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined ->
        table = :ets.new(table, @table_options)
        :ets.insert(table, {:catalog, %Catalog{}})
        table

      table_id ->
        table_id
    end
  end

  def load_all do
    catalog =
      build_catalog(
        DBC.all(Faction),
        Mangos.Repo.all(Mangos.ReputationSpilloverTemplate),
        Mangos.Repo.all(Mangos.CreatureOnkillReputation),
        Mangos.Repo.all(Mangos.ReputationRewardRate)
      )

    :ets.insert(__MODULE__, {:catalog, catalog})
    :ok
  end

  def catalog(table \\ __MODULE__) do
    case :ets.lookup(table, :catalog) do
      [{:catalog, %Catalog{} = catalog}] -> catalog
      _ -> %Catalog{}
    end
  end

  def put_catalog(%Catalog{} = catalog, table \\ __MODULE__) do
    :ets.insert(table, {:catalog, catalog})
    :ok
  end

  def faction(faction_id, table \\ __MODULE__) do
    table
    |> catalog()
    |> then(&Map.get(&1.factions, faction_id))
  end

  def build_catalog(faction_rows, spillover_rows, kill_rows, rate_rows) do
    %Catalog{
      factions:
        faction_rows
        |> Enum.filter(&(&1.reputation_index != @no_reputation_index))
        |> Map.new(fn row -> {row.id, definition(row)} end),
      spillovers: Map.new(spillover_rows, fn row -> {row.faction, spillovers(row)} end),
      kill_rewards: kill_rewards(kill_rows),
      rates:
        Map.new(rate_rows, fn row ->
          {row.faction, %{quest: row.quest_rate, kill: row.creature_rate, spell: row.spell_rate}}
        end)
    }
  end

  defp definition(row) do
    %Definition{
      id: row.id,
      index: row.reputation_index,
      name: row.name_en_gb,
      parent_faction_id: row.parent_faction,
      variants:
        Enum.map(0..3, fn index ->
          %Variant{
            race_mask: Map.fetch!(row, :"reputation_race_mask_#{index}"),
            class_mask: Map.fetch!(row, :"reputation_class_mask_#{index}"),
            base_standing: signed_32(Map.fetch!(row, :"reputation_base_#{index}")),
            flags: Map.fetch!(row, :"reputation_flags_#{index}")
          }
        end)
    }
  end

  defp spillovers(row) do
    Enum.flat_map(1..4, fn index ->
      faction_id = Map.fetch!(row, :"faction_#{index}")

      if faction_id > 0 do
        [
          %Spillover{
            faction_id: faction_id,
            rate: Map.fetch!(row, :"rate_#{index}"),
            max_rank: Map.fetch!(row, :"rank_#{index}")
          }
        ]
      else
        []
      end
    end)
  end

  defp kill_rewards(rows) do
    rows
    |> Enum.group_by(& &1.creature_id)
    |> Map.new(fn {creature_id, versions} ->
      row = Enum.max_by(versions, & &1.patch)
      {creature_id, kill_reward_slots(row)}
    end)
  end

  defp kill_reward_slots(row) do
    Enum.flat_map(1..2, fn index ->
      faction_id = Map.fetch!(row, :"reward_faction_#{index}")
      value = Map.fetch!(row, :"reward_value_#{index}")

      if faction_id > 0 and value != 0 do
        [
          %KillReward{
            faction_id: faction_id,
            value: value,
            max_rank: Map.fetch!(row, :"max_rank_#{index}"),
            team: reward_team(row.team_dependent, index),
            team_award?: Map.fetch!(row, :"team_award_#{index}") != 0
          }
        ]
      else
        []
      end
    end)
  end

  defp reward_team(team_dependent, 1) when team_dependent != 0, do: :alliance
  defp reward_team(team_dependent, 2) when team_dependent != 0, do: :horde
  defp reward_team(_team_dependent, _index), do: :both

  defp signed_32(value) when value > 2_147_483_647, do: value - 4_294_967_296
  defp signed_32(value), do: value
end
