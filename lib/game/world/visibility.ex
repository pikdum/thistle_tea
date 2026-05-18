defmodule ThistleTea.Game.World.Visibility do
  @moduledoc false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.Groups
  alias ThistleTea.Game.World.SpatialHash

  @group Groups
  @range 250

  def enter_player(%{visibility_cells: %MapSet{}} = state), do: state

  def enter_player(%{character: character, guid: guid} = state) do
    character = join_entity(character)
    cells = visible_cells(character)
    Enum.each(cells, &Group.monitor(@group, cell_key(&1)))

    state
    |> Map.put(:character, character)
    |> Map.put(:visibility_cells, cells)
    |> sync_visible_entities(guid, cells)
  end

  def enter_player(state), do: state

  def refresh_player(%{character: character, guid: guid, visibility_cells: old_cells} = state) do
    old_cell = entity_cell(character)
    character = refresh_entity(character)
    new_cell = entity_cell(character)

    if old_cell == new_cell do
      %{state | character: character}
    else
      new_cells = visible_cells(character)
      removed_cells = MapSet.difference(old_cells, new_cells)
      added_cells = MapSet.difference(new_cells, old_cells)

      Enum.each(removed_cells, &Group.demonitor(@group, cell_key(&1)))
      Enum.each(added_cells, &Group.monitor(@group, cell_key(&1)))

      state
      |> Map.put(:character, character)
      |> Map.put(:visibility_cells, new_cells)
      |> sync_visible_entities(guid, new_cells)
    end
  end

  def refresh_player(state), do: state

  def leave_player(%{character: character, visibility_cells: cells} = state) do
    Enum.each(cells, &Group.demonitor(@group, cell_key(&1)))
    character = leave_entity(character)

    state
    |> Map.put(:character, character)
    |> Map.delete(:visibility_cells)
    |> Map.put(:player_guids, [])
    |> Map.put(:mob_guids, [])
    |> Map.put(:tracked_entities, MapSet.new())
  end

  def leave_player(%{character: character} = state) do
    %{state | character: leave_entity(character)}
  end

  def leave_player(state), do: state

  def handle_events(%{guid: guid, visibility_cells: cells} = state, events) do
    Enum.reduce(events, state, fn
      %Group.Event{key: key, type: :joined, meta: %{guid: entity_guid} = meta}, state ->
        if cell_key?(cells, key) and entity_guid != guid do
          track_joined(state, meta)
        else
          state
        end

      %Group.Event{type: :left, meta: %{guid: entity_guid} = meta}, state ->
        track_left(state, entity_guid, Map.get(meta, :type))

      _event, state ->
        state
    end)
  end

  def handle_events(state, _events), do: state

  def join_entity(%{internal: %Internal{} = internal} = entity) do
    cell = current_cell(entity)

    if cell == internal.visibility_cell do
      entity
    else
      entity = leave_entity(entity)
      :ok = Group.join(@group, cell_key(cell), entity_meta(entity))
      put_visibility_cell(entity, cell)
    end
  end

  def join_entity(entity), do: entity

  def refresh_entity(%{internal: %Internal{} = internal} = entity) do
    cell = current_cell(entity)

    if cell == internal.visibility_cell do
      entity
    else
      entity
      |> leave_entity()
      |> join_entity()
    end
  end

  def refresh_entity(entity), do: entity

  def leave_entity(%{internal: %Internal{visibility_cell: nil}} = entity), do: entity

  def leave_entity(%{internal: %Internal{visibility_cell: cell}} = entity) do
    Group.leave(@group, cell_key(cell))
    put_visibility_cell(entity, nil)
  end

  def leave_entity(entity), do: entity

  def visible_cells(%{internal: %Internal{map: map}, movement_block: %MovementBlock{position: {x, y, z, _o}}}) do
    map
    |> SpatialHash.cells_in_range(x, y, z, @range)
    |> MapSet.new()
  end

  def current_cell(%{internal: %Internal{map: map}, movement_block: %MovementBlock{position: {x, y, z, _o}}}) do
    SpatialHash.cell(map, x, y, z)
  end

  def group_name, do: @group

  def cell_key({map, x, y}), do: "cell/#{map}/#{x}/#{y}"

  defp sync_visible_entities(%{tracked_entities: tracked} = state, self_guid, cells) do
    visible = visible_members(cells)
    visible_guids = MapSet.new(visible, & &1.guid)
    tracked = tracked || MapSet.new()

    tracked
    |> MapSet.difference(visible_guids)
    |> Enum.each(&Network.send_packet(%Message.SmsgDestroyObject{guid: &1}))

    visible_guids
    |> MapSet.difference(tracked)
    |> Enum.each(fn guid ->
      if guid != self_guid do
        Entity.request_update_from(guid, self_guid)
      end
    end)

    state
    |> Map.put(:tracked_entities, MapSet.intersection(tracked, visible_guids))
    |> put_entity_lists(visible)
  end

  defp sync_visible_entities(state, self_guid, cells) do
    sync_visible_entities(Map.put(state, :tracked_entities, MapSet.new()), self_guid, cells)
  end

  defp visible_members(cells) do
    cells
    |> Enum.flat_map(fn cell ->
      @group
      |> Group.members(cell_key(cell))
      |> Enum.map(fn {_pid, meta} -> meta end)
    end)
    |> Map.new(fn %{guid: guid} = meta -> {guid, meta} end)
    |> Map.values()
  end

  defp track_joined(state, %{guid: guid} = meta) do
    state = add_to_entity_lists(state, meta)

    if tracked?(state, guid) do
      state
    else
      Entity.request_update_from(guid, state.guid)
      state
    end
  end

  defp track_left(state, guid, type) do
    state = remove_from_entity_lists(state, guid, type)

    if tracked?(state, guid) and not currently_visible?(state, guid) do
      Network.send_packet(%Message.SmsgDestroyObject{guid: guid})
      Map.update(state, :tracked_entities, MapSet.new(), &MapSet.delete(&1, guid))
    else
      state
    end
  end

  defp currently_visible?(%{visibility_cells: cells}, guid) do
    case SpatialHash.get_entity(guid) do
      {^guid, map, x, y, z} -> MapSet.member?(cells, SpatialHash.cell(map, x, y, z))
      _ -> false
    end
  end

  defp currently_visible?(_state, _guid), do: false

  defp tracked?(state, guid) do
    state
    |> Map.get(:tracked_entities, MapSet.new())
    |> MapSet.member?(guid)
  end

  defp put_entity_lists(state, visible) do
    state
    |> Map.put(:player_guids, guids_for(visible, :player))
    |> Map.put(:mob_guids, guids_for(visible, :mob))
  end

  defp add_to_entity_lists(state, %{guid: guid, type: :player}) do
    Map.update(state, :player_guids, [guid], &Enum.uniq([guid | &1]))
  end

  defp add_to_entity_lists(state, %{guid: guid, type: :mob}) do
    Map.update(state, :mob_guids, [guid], &Enum.uniq([guid | &1]))
  end

  defp add_to_entity_lists(state, _meta), do: state

  defp remove_from_entity_lists(state, guid, :player) do
    Map.update(state, :player_guids, [], &List.delete(&1, guid))
  end

  defp remove_from_entity_lists(state, guid, :mob) do
    Map.update(state, :mob_guids, [], &List.delete(&1, guid))
  end

  defp remove_from_entity_lists(state, _guid, _type), do: state

  defp guids_for(visible, type) do
    visible
    |> Enum.filter(&(&1.type == type))
    |> Enum.map(& &1.guid)
  end

  defp cell_key?(cells, key) do
    Enum.any?(cells, &(cell_key(&1) == key))
  end

  defp entity_meta(%{object: %{guid: guid}} = entity) do
    %{guid: guid, type: Guid.entity_type(guid), cell: current_cell(entity)}
  end

  defp entity_cell(%{internal: %Internal{visibility_cell: cell}}), do: cell

  defp put_visibility_cell(%{internal: %Internal{} = internal} = entity, cell) do
    %{entity | internal: %{internal | visibility_cell: cell}}
  end
end
