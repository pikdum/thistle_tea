defmodule ThistleTea.Game.Entity.Logic.Reputation do
  @moduledoc """
  Pure faction-standing rules: race/class base selection, rank thresholds,
  standing changes and spillover, visibility, at-war, and inactive state.
  """

  import Bitwise

  alias ThistleTea.Game.Entity.Data.Reputation
  alias ThistleTea.Game.Entity.Data.Reputation.Catalog
  alias ThistleTea.Game.Entity.Data.Reputation.Change
  alias ThistleTea.Game.Entity.Data.Reputation.Definition
  alias ThistleTea.Game.Entity.Data.Reputation.Spillover
  alias ThistleTea.Game.Entity.Data.Reputation.State
  alias ThistleTea.Game.Entity.Data.Reputation.Variant
  alias ThistleTea.Game.Entity.Logic.Experience

  @bottom -42_000
  @cap 42_999
  @visible 0x01
  @at_war 0x02
  @hidden 0x04
  @invisible_forced 0x08
  @peace_forced 0x10
  @inactive 0x20

  @ranks [
    {:hated, -42_000},
    {:hostile, -6_000},
    {:unfriendly, -3_000},
    {:neutral, 0},
    {:friendly, 3_000},
    {:honored, 9_000},
    {:revered, 21_000},
    {:exalted, 42_000}
  ]

  def bottom, do: @bottom
  def cap, do: @cap
  def ranks, do: Enum.map(@ranks, &elem(&1, 0))

  def initialize(%Catalog{} = catalog, race, class) do
    {states, ranks} =
      catalog.factions
      |> Map.values()
      |> Enum.reduce({%{}, %{}}, fn %Definition{} = definition, {states, ranks} ->
        variant = matching_variant(definition, race, class)
        base = if variant, do: variant.base_standing, else: 0

        state = %State{
          faction_id: definition.id,
          index: definition.index,
          flags: if(variant, do: variant.flags, else: 0)
        }

        {Map.put(states, definition.id, state), Map.put(ranks, definition.id, rank(base))}
      end)

    %Reputation{states: states, ranks: ranks}
  end

  def normalize(%Reputation{} = reputation, %Catalog{} = catalog, race, class) do
    initialized = initialize(catalog, race, class)

    states =
      Map.merge(initialized.states, Map.take(reputation.states, Map.keys(catalog.factions)), fn
        _faction_id, initial, existing ->
          %{existing | index: initial.index}
      end)

    ranks =
      Map.new(states, fn {faction_id, %State{standing: standing}} ->
        definition = Map.fetch!(catalog.factions, faction_id)
        total = base_standing(definition, race, class) + standing
        {faction_id, rank(total)}
      end)

    %{reputation | states: states, ranks: ranks}
  end

  def state(%Reputation{states: states}, faction_id), do: Map.get(states, faction_id)

  def state_by_index(%Reputation{states: states}, index) do
    Enum.find_value(states, fn
      {_faction_id, %State{index: ^index} = state} -> state
      _entry -> nil
    end)
  end

  def standing(%Reputation{} = reputation, %Catalog{} = catalog, faction_id, race, class) do
    case {state(reputation, faction_id), Map.get(catalog.factions, faction_id)} do
      {%State{standing: offset}, %Definition{} = definition} ->
        base_standing(definition, race, class) + offset

      _ ->
        0
    end
  end

  def base_standing(%Definition{} = definition, race, class) do
    case matching_variant(definition, race, class) do
      %Variant{base_standing: base} -> base
      nil -> 0
    end
  end

  def rank(standing) when is_integer(standing) do
    @ranks
    |> Enum.reverse()
    |> Enum.find_value(:hated, fn {rank, minimum} ->
      if standing >= minimum, do: rank
    end)
  end

  def rank_value(rank) when is_atom(rank) do
    Enum.find_index(@ranks, fn {candidate, _minimum} -> candidate == rank end)
  end

  def rank_value(rank) when is_integer(rank) and rank in 0..7, do: rank
  def rank_value(_rank), do: nil

  def rank_minimum(rank) do
    case rank_value(rank) do
      value when is_integer(value) -> @ranks |> Enum.at(value) |> elem(1)
      nil -> nil
    end
  end

  def calculate_gain(value, rate, level_rate, bonus, random \\ &:rand.uniform/0)
      when is_integer(value) and is_number(rate) and is_number(level_rate) and is_integer(bonus) and
             is_function(random, 0) do
    if rate <= 0 or 100 + bonus <= 0 do
      0
    else
      value
      |> Kernel.*(rate * level_rate * (100 + bonus) / 100)
      |> dither(random.())
    end
  end

  def level_rate(_source, value, _player_level, _content_level) when value <= 0, do: 1.0

  def level_rate(:kill, _value, player_level, creature_level) do
    if creature_level <= Experience.gray_level(player_level), do: 0.2, else: 1.0
  end

  def level_rate(:quest, _value, player_level, quest_level) do
    case max(player_level - quest_level - 5, 0) do
      0 -> 1.0
      1 -> 0.8
      2 -> 0.6
      3 -> 0.4
      _ -> 0.2
    end
  end

  def level_rate(_source, _value, _player_level, _content_level), do: 1.0

  def modify(%Reputation{} = reputation, %Catalog{} = catalog, faction_id, delta, context, opts \\ [])
      when is_integer(delta) do
    changes =
      if Keyword.get(opts, :spillover?, true) do
        spillover_changes(reputation, catalog, faction_id, delta, context)
      else
        []
      end

    apply_changes(reputation, catalog, changes ++ [{faction_id, delta}], context)
  end

  def set(%Reputation{} = reputation, %Catalog{} = catalog, faction_id, value, context) when is_integer(value) do
    current = standing(reputation, catalog, faction_id, context.race, context.class)
    modify(reputation, catalog, faction_id, value - current, context, spillover?: false)
  end

  def set_visible(%Reputation{} = reputation, faction_id) do
    with %State{} = state <- state(reputation, faction_id),
         false <- flag?(state.flags, @hidden ||| @invisible_forced),
         false <- visible?(state) do
      updated = %{state | flags: state.flags ||| @visible}
      {:ok, put_state(reputation, updated), change(updated)}
    else
      _ -> {:error, :not_allowed}
    end
  end

  def set_at_war(%Reputation{} = reputation, %Catalog{} = catalog, index, enabled, context) when is_boolean(enabled) do
    with %State{} = state <- state_by_index(reputation, index),
         %Definition{} = definition <- Map.get(catalog.factions, state.faction_id),
         true <- war_change_allowed?(state, definition, enabled, context) do
      flags = put_flag(state.flags, @at_war, enabled)
      updated = %{state | flags: flags}
      {:ok, put_state(reputation, updated), change(updated)}
    else
      _ -> {:error, :not_allowed}
    end
  end

  def set_inactive(%Reputation{} = reputation, index, enabled) when is_boolean(enabled) do
    with %State{} = state <- state_by_index(reputation, index),
         true <- inactive_change_allowed?(state, enabled) do
      updated = %{state | flags: put_flag(state.flags, @inactive, enabled)}
      {:ok, put_state(reputation, updated), change(updated)}
    else
      _ -> {:error, :not_allowed}
    end
  end

  def set_temporary_at_war(%Reputation{} = reputation, faction_id) when is_integer(faction_id) do
    with %State{} = state <- state(reputation, faction_id),
         false <- at_war?(reputation, faction_id),
         true <- temporary_war_allowed?(reputation, state) do
      updated = %{state | flags: put_flag(state.flags, @at_war, true)}

      reputation = %{
        reputation
        | states: Map.put(reputation.states, faction_id, updated),
          temporary_at_war: MapSet.put(reputation.temporary_at_war, faction_id)
      }

      {:ok, reputation, change(updated)}
    else
      _not_changed -> {:error, :not_allowed}
    end
  end

  def set_temporary_at_war(%Reputation{}, _faction_id), do: {:error, :not_allowed}

  def clear_temporary_at_war(%Reputation{} = reputation) do
    {reputation, changes} =
      Enum.reduce(reputation.temporary_at_war, {reputation, []}, fn faction_id, {reputation, changes} ->
        state = state(reputation, faction_id)
        rank = Map.get(reputation.ranks, faction_id)

        if state && at_war?(reputation, faction_id) && rank not in [:hated, :hostile] do
          updated = %{state | flags: put_flag(state.flags, @at_war, false)}
          {put_state(reputation, updated), changes ++ [change(updated)]}
        else
          {reputation, changes}
        end
      end)

    {%{reputation | temporary_at_war: MapSet.new()}, changes}
  end

  def at_war?(%Reputation{} = reputation, faction_id) do
    case state(reputation, faction_id) do
      %State{flags: flags} -> flag?(flags, @at_war)
      nil -> false
    end
  end

  def visible?(%State{flags: flags}), do: flag?(flags, @visible)
  def inactive?(%State{flags: flags}), do: flag?(flags, @inactive)

  def hostile?(%Reputation{} = reputation, %Catalog{} = catalog, faction_id, context) do
    at_war?(reputation, faction_id) or
      rank(standing(reputation, catalog, faction_id, context.race, context.class)) in [:hated, :hostile]
  end

  defp apply_changes(reputation, catalog, changes, context) do
    Enum.reduce(changes, {reputation, []}, fn {faction_id, delta}, {reputation, emitted} ->
      case apply_change(reputation, catalog, faction_id, delta, context) do
        {:ok, reputation, change} -> {reputation, emitted ++ [change]}
        :ignored -> {reputation, emitted}
      end
    end)
  end

  defp apply_change(reputation, catalog, faction_id, delta, context) do
    with %State{} = state <- state(reputation, faction_id),
         %Definition{} = definition <- Map.get(catalog.factions, faction_id) do
      base = base_standing(definition, context.race, context.class)
      total = (base + state.standing + delta) |> max(@bottom) |> min(@cap)
      flags = state.flags |> make_visible() |> force_war_if_hostile(total)
      updated = %{state | standing: total - base, flags: flags}
      {:ok, put_state(reputation, updated, rank(total)), change(updated)}
    else
      _ -> :ignored
    end
  end

  defp spillover_changes(reputation, catalog, faction_id, delta, context) do
    catalog.spillovers
    |> Map.get(faction_id, [])
    |> Enum.flat_map(fn %Spillover{} = spillover ->
      standing = standing(reputation, catalog, spillover.faction_id, context.race, context.class)

      if rank_value(rank(standing)) <= rank_value(spillover.max_rank) do
        [{spillover.faction_id, trunc(delta * spillover.rate)}]
      else
        []
      end
    end)
  end

  defp matching_variant(%Definition{variants: variants}, race, class) do
    race_mask = if is_integer(race) and race > 0, do: 1 <<< (race - 1), else: 0
    class_mask = if is_integer(class) and class > 0, do: 1 <<< (class - 1), else: 0

    Enum.find(variants, fn %Variant{} = variant ->
      (variant.race_mask == 0 or (variant.race_mask &&& race_mask) != 0) and
        (variant.class_mask == 0 or (variant.class_mask &&& class_mask) != 0)
    end)
  end

  defp war_change_allowed?(%State{flags: flags} = state, definition, enabled, context) do
    flag?(flags, @at_war) != enabled and
      not flag?(flags, @hidden ||| @invisible_forced) and
      not (enabled and flag?(flags, @peace_forced) and
             rank(total_standing(state, definition, context)) != :hated)
  end

  defp temporary_war_allowed?(%Reputation{} = reputation, %State{flags: flags, faction_id: faction_id}) do
    not flag?(flags, @hidden ||| @invisible_forced) and
      not (flag?(flags, @peace_forced) and Map.get(reputation.ranks, faction_id) != :hated)
  end

  defp inactive_change_allowed?(%State{flags: flags}, true) do
    not flag?(flags, @hidden ||| @invisible_forced) and flag?(flags, @visible)
  end

  defp inactive_change_allowed?(%State{}, false), do: true

  defp total_standing(%State{standing: standing}, %Definition{} = definition, context) do
    standing + base_standing(definition, context.race, context.class)
  end

  defp make_visible(flags) do
    if flag?(flags, @hidden ||| @invisible_forced), do: flags, else: flags ||| @visible
  end

  defp force_war_if_hostile(flags, standing) do
    if rank(standing) in [:hated, :hostile], do: flags ||| @at_war, else: flags
  end

  defp put_flag(flags, flag, true), do: flags ||| flag
  defp put_flag(flags, flag, false), do: flags &&& bnot(flag)
  defp flag?(flags, flag), do: (flags &&& flag) != 0

  defp put_state(%Reputation{} = reputation, %State{} = state) do
    %{reputation | states: Map.put(reputation.states, state.faction_id, state)}
  end

  defp put_state(%Reputation{} = reputation, %State{} = state, rank) do
    %{
      reputation
      | states: Map.put(reputation.states, state.faction_id, state),
        ranks: Map.put(reputation.ranks, state.faction_id, rank)
    }
  end

  defp change(%State{} = state) do
    %Change{
      faction_id: state.faction_id,
      index: state.index,
      standing: state.standing,
      flags: state.flags
    }
  end

  defp dither(value, random) when value < 0, do: -floor(abs(value) + random)
  defp dither(value, random), do: floor(value + random)
end
