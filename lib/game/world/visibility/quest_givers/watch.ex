defmodule ThistleTea.Game.World.Visibility.QuestGivers.Watch do
  @moduledoc """
  Compiles condition requirements into cheap owner-state comparisons and
  notifications. Time gates schedule their next truth change, without polling.
  """

  alias ThistleTea.Game.Core.Condition
  alias ThistleTea.Game.Core.Condition.Requirements
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Quest.QuestRequirements
  alias ThistleTea.Game.World.Entity.Player.Quests
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Topics

  defstruct visible: MapSet.new(), fields: [], keys: [], minutes: [], spatial?: false

  def build(visible) do
    conditions =
      visible
      |> Enum.flat_map(fn guid ->
        {given, ended} = Quests.npc_quests(guid)
        given ++ ended
      end)
      |> Enum.flat_map(&QuestRequirements.condition_quests/1)
      |> Enum.map(& &1.required_condition)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    requirements = Requirements.plan(conditions)

    %__MODULE__{
      visible: visible,
      fields: requirements |> Enum.flat_map(&fields/1) |> Enum.uniq() |> Enum.sort(),
      keys: for({:saved_variable, index} <- requirements, do: Topics.server_variable(index)),
      minutes: conditions |> Enum.flat_map(&minutes/1) |> Enum.uniq(),
      spatial?: Requirements.environment_conditions(conditions) != []
    }
  end

  def fingerprint(%__MODULE__{fields: fields, spatial?: spatial?}, %Character{} = viewer) do
    base =
      {viewer.unit.level, viewer.unit.race, viewer.unit.class, viewer.player.quest_log, viewer.player.rewarded_quests,
       viewer.player.skills, viewer.player.skill_bonuses, viewer.player.reputation, viewer.internal.area,
       viewer.internal.world}

    {base, Enum.map(fields, &value(&1, viewer)), if(spatial?, do: viewer.movement_block.position)}
  end

  def next_delay(%__MODULE__{minutes: []}, _now), do: nil

  def next_delay(%__MODULE__{minutes: minutes}, %NaiveDateTime{} = now) do
    elapsed = (now.hour * 60 + now.minute) * 60_000 + now.second * 1_000 + div(elem(now.microsecond, 0), 1_000)

    minutes
    |> Enum.map(fn minute ->
      case rem(minute * 60_000 - elapsed + 86_400_000, 86_400_000) do
        0 -> 86_400_000
        delay -> delay
      end
    end)
    |> Enum.min()
  end

  defp fields({:subject, _target, field}), do: [field]
  defp fields({:aura, _target, _spell, _effect}), do: [:auras]
  defp fields({:area_explored, _target, _id}), do: [:explored_areas]
  defp fields(_requirement), do: []

  defp value(:spell_ids, viewer), do: viewer.internal.spellbook
  defp value(:pet, viewer), do: viewer.internal.companion
  defp value(:health, viewer), do: {viewer.unit.health, viewer.unit.max_health}
  defp value(:mana, viewer), do: {viewer.unit.power1, viewer.unit.max_power1}
  defp value(:alive, viewer), do: {viewer.unit.health, viewer.player.flags}
  defp value(:combat, viewer), do: viewer.internal.in_combat
  defp value(:group, viewer), do: Metadata.query(viewer.object.guid, [:group_id])
  defp value(:honor_rank, viewer), do: viewer.player.honor_rank
  defp value(:explored_areas, viewer), do: viewer.player.explored_zones
  defp value(:moving, viewer), do: {viewer.movement_block.movement_flags, viewer.movement_block.spline_nodes}
  defp value(:gender, viewer), do: viewer.unit.gender
  defp value(:auras, viewer), do: Enum.map(viewer.unit.auras || [], &{&1.spell.id, &1.auras, &1.stacks})
  defp value(_field, _viewer), do: nil

  defp minutes(%Condition{type: :local_time, value1: sh, value2: sm, value3: eh, value4: em}),
    do: [sh * 60 + sm, rem(eh * 60 + em + 1, 1440)]

  defp minutes(%Condition{children: children}), do: Enum.flat_map(children, &minutes/1)
end
