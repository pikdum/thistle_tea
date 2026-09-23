defmodule ThistleTea.Game.Instance.Lockouts do
  @moduledoc "Permanent player and group raid bindings, independent of temporary copy ownership."

  alias ThistleTea.Game.Party.Group
  alias ThistleTea.Game.WorldRef

  defstruct bindings: %{}

  def world_for(%__MODULE__{bindings: bindings}, map_id, owner), do: Map.get(bindings, {map_id, owner})

  def worlds(%__MODULE__{bindings: bindings}, owner) do
    bindings
    |> Enum.flat_map(fn
      {{_map, ^owner}, world} -> [world]
      _ -> []
    end)
    |> Enum.sort_by(& &1.map_id)
  end

  def saved?(%__MODULE__{bindings: bindings}, %WorldRef{} = world), do: world in Map.values(bindings)

  def check(%__MODULE__{} = lockouts, %WorldRef{} = world, owner, guid) do
    if Enum.all?([owner, {:player, guid}], &(world_for(lockouts, world.map_id, &1) in [nil, world])),
      do: :ok,
      else: {:error, :instance_unavailable}
  end

  def bind_players(%__MODULE__{} = lockouts, %WorldRef{} = world, members, group) do
    newly_saved = Enum.filter(members, &is_nil(world_for(lockouts, world.map_id, {:player, &1})))
    lockouts = Enum.reduce(newly_saved, lockouts, &bind(&2, world, {:player, &1}))
    {newly_saved, bind_group(lockouts, world, members, group)}
  end

  def inherit(%__MODULE__{} = lockouts, %WorldRef{} = world, owner, guid) do
    if world_for(lockouts, world.map_id, owner) == world,
      do: bind(lockouts, world, {:player, guid}),
      else: lockouts
  end

  def group_changed(%__MODULE__{} = lockouts, nil, %Group{id: id, leader: leader}) do
    Enum.reduce(worlds(lockouts, {:player, leader}), lockouts, &bind(&2, &1, {:party, id}))
  end

  def group_changed(%__MODULE__{} = lockouts, %Group{id: id}, nil) do
    %{lockouts | bindings: Map.reject(lockouts.bindings, fn {{_map, owner}, _world} -> owner == {:party, id} end)}
  end

  def group_changed(
        %__MODULE__{} = lockouts,
        %Group{id: id, leader: previous} = old_group,
        %Group{id: id, leader: current} = new_group
      )
      when previous != current do
    lockouts |> group_changed(old_group, nil) |> group_changed(nil, new_group)
  end

  def group_changed(%__MODULE__{} = lockouts, _previous, _current), do: lockouts

  def reset_map(%__MODULE__{} = lockouts, map_id) do
    %{lockouts | bindings: Map.reject(lockouts.bindings, fn {{map, _owner}, _world} -> map == map_id end)}
  end

  defp bind_group(lockouts, world, members, %Group{id: id, leader: leader}) do
    if leader in members, do: bind(lockouts, world, {:party, id}), else: lockouts
  end

  defp bind_group(lockouts, _world, _members, nil), do: lockouts

  defp bind(lockouts, world, owner) do
    %{lockouts | bindings: Map.put_new(lockouts.bindings, {world.map_id, owner}, world)}
  end
end
