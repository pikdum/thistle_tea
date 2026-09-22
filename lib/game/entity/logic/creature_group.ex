defmodule ThistleTea.Game.Entity.Logic.CreatureGroup do
  @moduledoc """
  Creature-group membership and coordinated combat lifecycle decisions.
  Member keys identify spawns within one world copy, independently of incarnations.
  """

  import Bitwise

  @enforce_keys [:leader]
  defstruct [:leader, members: %{}, flags: 0]

  defmodule Member do
    @moduledoc false
    defstruct distance: 0.0, angle: 0.0, flags: 0
  end

  def new(leader), do: %__MODULE__{leader: leader}

  def add(%__MODULE__{leader: leader} = group, leader, %Member{}), do: group

  def add(%__MODULE__{} = group, member, %Member{} = settings) do
    %{group | members: Map.put(group.members, member, settings), flags: group.flags ||| settings.flags}
  end

  def remove(%__MODULE__{} = group, member), do: %{group | members: Map.delete(group.members, member)}

  def member_ids(%__MODULE__{} = group), do: [group.leader | Enum.sort(Map.keys(group.members))]

  def actions(%__MODULE__{} = group, source, {:attack, target}, actors) do
    if flag?(group, 0x02) do
      recipients(group, source, actors, &(&1.alive? and not &1.combat?))
      |> Enum.map(&{&1, {:attack, target}})
    else
      []
    end
  end

  def actions(%__MODULE__{} = group, source, :evade, actors) do
    evade =
      if flag?(group, 0x04) do
        recipients(group, source, actors, &(&1.alive? and &1.combat?))
        |> Enum.map(&{&1, :evade})
      else
        []
      end

    master_evade? =
      source == group.leader or (flag?(group, 0x04) and match?(%{present?: true, alive?: true}, actors[group.leader]))

    if flag?(group, 0x20) or (flag?(group, 0x10) and master_evade?) do
      evade ++ respawns(group, source, actors)
    else
      evade
    end
  end

  def actions(%__MODULE__{} = group, source, :respawn, actors) do
    if flag?(group, 0x08), do: respawns(group, source, actors), else: []
  end

  def actions(%__MODULE__{} = group, source, :death, actors) do
    group
    |> recipients(source, actors, & &1.alive?)
    |> Enum.filter(fn id -> if id == group.leader, do: flag?(group, 0x40), else: flag?(group, 0x80) end)
    |> Enum.map(&{&1, {:member_died, source, source == group.leader}})
  end

  def actions(%__MODULE__{}, _source, _event, _actors), do: []

  def dead?(%__MODULE__{} = group, source, actors) do
    recipients(group, source, actors, & &1.alive?) == []
  end

  defp respawns(group, source, actors) do
    recipients(group, source, actors, &(not &1.alive?)) |> Enum.map(&{&1, :respawn})
  end

  defp recipients(group, source, actors, predicate) do
    group
    |> member_ids()
    |> Enum.reject(&(&1 == source))
    |> Enum.filter(fn id ->
      case Map.get(actors, id) do
        %{present?: true} = actor -> predicate.(actor)
        _missing -> false
      end
    end)
  end

  defp flag?(%__MODULE__{flags: flags}, flag), do: (flags &&& flag) != 0
end
