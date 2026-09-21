defmodule ThistleTea.Game.Entity.Logic.QuestGraph do
  @moduledoc """
  Compiles signed prerequisites, exclusive groups, chain links, and breadcrumb
  relationships into immutable quest templates without runtime catalog reads.
  """

  alias ThistleTea.Game.Entity.Data.Quest
  alias ThistleTea.Game.Entity.Data.QuestDependencies
  alias ThistleTea.Game.Entity.Data.QuestDependencies.Prerequisite

  def compile(quests) when is_list(quests) do
    catalog = Map.new(quests, &{&1.id, &1})
    groups = Enum.group_by(quests, & &1.exclusive_group)
    incoming = Enum.group_by(quests, &abs(&1.next_quest_id))
    previous_chain = Enum.group_by(quests, & &1.next_quest_in_chain)
    paths = Map.new(quests, &{&1.id, breadcrumb_path(&1, catalog, MapSet.new())})
    breadcrumbs = dependent_breadcrumbs(paths, catalog)

    resolved =
      Map.new(quests, fn quest ->
        dependencies = %QuestDependencies{
          prerequisites: prerequisites(quest, catalog, groups, incoming),
          exclusive_quests: exclusive_quests(quest, groups),
          previous_chain_quests: previous_chain |> Map.get(quest.id, []) |> Enum.map(& &1.id) |> Enum.sort(),
          next_chain_quest: related(Map.get(catalog, quest.next_quest_in_chain)),
          dependent_breadcrumb_quests: Map.get(breadcrumbs, quest.id, []),
          valid?: Map.fetch!(paths, quest.id) != :invalid
        }

        {quest.id, %{quest | dependencies: dependencies}}
      end)

    quests
    |> Enum.sort_by(& &1.id)
    |> Enum.map(fn quest ->
      quest = Map.fetch!(resolved, quest.id)
      targets = if is_list(paths[quest.id]), do: Enum.map(paths[quest.id], &Map.fetch!(resolved, &1)), else: []
      %{quest | dependencies: %{quest.dependencies | breadcrumb_targets: targets}}
    end)
  end

  defp prerequisites(%Quest{} = quest, catalog, groups, incoming) do
    direct =
      case Map.get(catalog, abs(quest.prev_quest_id)) do
        %Quest{breadcrumb_for_quest_id: 0} -> [quest.prev_quest_id]
        _ -> []
      end

    inferred =
      incoming
      |> Map.get(quest.id, [])
      |> Enum.sort_by(& &1.id)
      |> Enum.map(fn previous -> if previous.next_quest_id < 0, do: -previous.id, else: previous.id end)

    (direct ++ inferred)
    |> Enum.uniq()
    |> Enum.map(fn signed_id ->
      previous = Map.fetch!(catalog, abs(signed_id))

      group =
        if previous.exclusive_group < 0,
          do: groups |> Map.fetch!(previous.exclusive_group) |> Enum.map(& &1.id) |> Enum.sort(),
          else: [previous.id]

      %Prerequisite{quest_id: previous.id, state: if(signed_id < 0, do: :current, else: :rewarded), group_quests: group}
    end)
  end

  defp exclusive_quests(%Quest{exclusive_group: group, id: id}, groups) when group > 0 do
    groups |> Map.fetch!(group) |> Enum.reject(&(&1.id == id)) |> Enum.map(&related/1) |> Enum.sort()
  end

  defp exclusive_quests(%Quest{}, _groups), do: []

  defp related(%Quest{} = quest), do: {quest.id, Quest.repeatable?(quest)}
  defp related(nil), do: nil

  defp breadcrumb_path(%Quest{breadcrumb_for_quest_id: 0}, _catalog, _seen), do: []
  defp breadcrumb_path(nil, _catalog, _seen), do: :invalid

  defp breadcrumb_path(%Quest{id: id, breadcrumb_for_quest_id: target}, catalog, seen) do
    if MapSet.member?(seen, id) do
      :invalid
    else
      prepend_breadcrumb(target, breadcrumb_path(Map.get(catalog, target), catalog, MapSet.put(seen, id)))
    end
  end

  defp prepend_breadcrumb(_target, :invalid), do: :invalid
  defp prepend_breadcrumb(target, path), do: [target | path]

  defp dependent_breadcrumbs(paths, catalog) do
    paths
    |> Enum.flat_map(fn
      {source, path} when is_list(path) -> Enum.map(path, &{&1, related(Map.fetch!(catalog, source))})
      _ -> []
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {id, sources} -> {id, Enum.sort(sources)} end)
  end
end
