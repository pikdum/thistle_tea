defmodule ThistleTea.Game.World.Visibility do
  @moduledoc """
  Cell-based visibility: keeps each player session's `visibility_cells` and
  `tracked_entities` in sync with the world (sole owner of both keys),
  exchanges join/leave events through cell groups, and sends create/destroy
  packets as entities move in and out of view.
  """

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Corpse
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.StealthDetection
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Math
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.SpatialGrid
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.ChaseWatch
  alias ThistleTea.Game.World.Groups
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.System.CellActivator
  alias ThistleTea.Game.World.System.Party, as: PartySystem
  alias ThistleTea.Game.World.Transports
  alias ThistleTea.Game.World.Visibility.Filter
  alias ThistleTea.Game.World.Visibility.QuestGivers
  alias ThistleTea.Game.WorldRef

  @group Groups
  @range 250
  @stealth_detection_ms 500

  def enter_player(%{visibility_cells: %MapSet{}} = state), do: state

  def enter_player(%{character: %{} = character, guid: guid} = state) when is_integer(guid) do
    character = join_entity(character)
    cells = visible_cells(character)
    activate_cells(state, cells)
    Enum.each(cells, &Group.monitor(@group, cell_key(&1)))

    state
    |> Map.put(:character, character)
    |> Map.put(:visibility_cells, cells)
    |> sync_visible_entities(guid, cells)
    |> schedule_stealth_detection()
  end

  def enter_player(state), do: state

  def refresh_player(%{character: character, guid: guid, visibility_cells: %MapSet{} = old_cells} = state) do
    character = refresh_entity(character)
    new_cells = viewpoint_cells(state) || visible_cells(character)

    state
    |> Map.put(:character, character)
    |> sync_visibility_cells(guid, old_cells, new_cells)
  end

  def refresh_player(state), do: state

  def select_viewpoint(%{ready: true} = state, 0), do: reset_viewpoint(state)

  def select_viewpoint(%{ready: true, character: %Character{player: %{farsight: guid}}} = state, 1),
    do: set_viewpoint(state, guid)

  def select_viewpoint(state, _operation), do: state

  def set_viewpoint(
        %{guid: viewer_guid, character: %{internal: %{world: world}}, visibility_cells: %MapSet{} = old_cells} = state,
        viewpoint_guid
      )
      when is_integer(viewpoint_guid) and viewpoint_guid > 0 do
    case viewpoint_location(viewpoint_guid) do
      {^world, x, y, z} ->
        new_cells = visible_cells_at(world, x, y, z)
        ChaseWatch.watch(viewpoint_guid, self(), {x, y, z}, 50.0)

        state
        |> put_viewpoint(viewpoint_guid)
        |> sync_visibility_cells(viewer_guid, old_cells, new_cells)

      _missing ->
        state
    end
  end

  def set_viewpoint(state, _viewpoint_guid), do: state

  def refresh_viewpoint(%{viewpoint_guid: guid} = state, guid) when is_integer(guid) and guid > 0 do
    set_viewpoint(state, guid)
  end

  def refresh_viewpoint(state, _guid), do: state

  def reset_viewpoint(
        %{guid: viewer_guid, character: %Character{} = character, visibility_cells: %MapSet{} = old_cells} = state
      ) do
    ChaseWatch.unwatch(self())

    state
    |> put_viewpoint(nil)
    |> sync_visibility_cells(viewer_guid, old_cells, visible_cells(character))
  end

  def reset_viewpoint(state), do: put_viewpoint(state, nil)

  def leave_player(%{character: character, visibility_cells: %MapSet{} = cells} = state) do
    state = cancel_stealth_detection(state)
    ChaseWatch.unwatch(self())
    Enum.each(cells, &Group.demonitor(@group, cell_key(&1)))
    character = leave_entity(character)

    state
    |> Map.put(:character, character)
    |> put_viewpoint(nil)
    |> Map.put(:visibility_cells, nil)
    |> Map.put(:player_guids, [])
    |> Map.put(:mob_guids, [])
    |> Map.put(:tracked_entities, MapSet.new())
  end

  def leave_player(%{character: character} = state) do
    ChaseWatch.unwatch(self())
    state = cancel_stealth_detection(state)
    %{state | character: leave_entity(character)}
  end

  def leave_player(state), do: state

  def handle_events(%{guid: guid, visibility_cells: %MapSet{} = cells} = state, events) do
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

  def visible_cells(%{internal: %Internal{world: world}, movement_block: %MovementBlock{position: {x, y, z, _o}}}) do
    visible_cells_at(world, x, y, z)
  end

  def current_cell(%{internal: %Internal{world: world}, movement_block: %MovementBlock{position: {x, y, z, _o}}}) do
    SpatialGrid.cell(world, x, y, z)
  end

  def group_name, do: @group

  def cell_key({%WorldRef{map_id: map_id, instance_id: instance_id}, x, y}) do
    "cell/#{map_id}/#{instance_id || "world"}/#{x}/#{y}"
  end

  def cell_key({map_id, x, y}) when is_integer(map_id) do
    cell_key({WorldRef.open(map_id), x, y})
  end

  def resync_player(%{guid: guid, visibility_cells: %MapSet{} = cells} = state) do
    sync_visible_entities(state, guid, cells)
  end

  def resync_player(state), do: state

  def reevaluate_entity(%{visibility_cells: %MapSet{}, guid: self_guid} = state, guid) when guid != self_guid do
    visible? = currently_visible?(state, guid) and can_see?(state, guid)

    cond do
      visible? and not tracked?(state, guid) ->
        Entity.request_update_from(guid, self_guid)
        state

      not visible? and tracked?(state, guid) ->
        send_destroy(guid)
        untrack_entity(state, guid)

      true ->
        state
    end
  end

  def reevaluate_entity(state, _guid), do: state

  def track_entities(state, %MapSet{} = guids) do
    Map.update(state, :tracked_entities, guids, &MapSet.union(&1, guids))
  end

  def untrack_entity(state, guid) when is_integer(guid) do
    state
    |> Map.update(:tracked_entities, MapSet.new(), &MapSet.delete(&1, guid))
    |> QuestGivers.forget(guid)
  end

  def tracked?(state, guid) when is_integer(guid) do
    state
    |> Map.get(:tracked_entities, MapSet.new())
    |> MapSet.member?(guid)
  end

  def tracked?(_state, _guid), do: false

  def notify_visibility_changed(%{object: %{guid: guid}} = character) do
    character
    |> World.nearby_players()
    |> Enum.each(fn {player_guid, _distance} ->
      if player_guid != guid do
        Entity.visibility_changed(player_guid, guid)
      end
    end)
  end

  def notify_visibility_changed(_character), do: :ok

  def can_see?(%{guid: guid}, guid), do: true

  def can_see?(state, guid) do
    case Map.get(state, :character) do
      %Character{} = character ->
        ghost? = Death.ghost?(character)
        type = Guid.entity_type(guid)
        distance = if ghost? and type == :mob, do: corpse_distance(character, guid)
        meta = Metadata.get(guid) || %{}

        Filter.can_see?(ghost?, type, meta, distance) and
          (owned_or_grouped?(character.object.guid, guid, meta) or detectable?(character, guid, meta))

      _missing ->
        true
    end
  end

  def stealth_detection_tick(%{stealth_detection_ref: ref, visibility_cells: %MapSet{}} = state, ref)
      when is_reference(ref) do
    (Map.get(state, :player_guids, []) ++ Map.get(state, :mob_guids, []))
    |> Enum.filter(&match?(%{stealthed?: true}, Metadata.get(&1)))
    |> Enum.reduce(state, &reevaluate_entity(&2, &1))
    |> QuestGivers.refresh()
    |> schedule_stealth_detection()
  end

  def stealth_detection_tick(state, _ref), do: state

  def schedule_stealth_detection(%{visibility_cells: %MapSet{}} = state) do
    ref = :erlang.start_timer(@stealth_detection_ms, self(), :stealth_detection)
    Map.put(state, :stealth_detection_ref, ref)
  end

  def schedule_stealth_detection(state), do: state

  defp cancel_stealth_detection(state) do
    case Map.get(state, :stealth_detection_ref) do
      ref when is_reference(ref) -> Process.cancel_timer(ref)
      _ -> :ok
    end

    Map.put(state, :stealth_detection_ref, nil)
  end

  defp detectable?(character, guid, meta) do
    detector = character |> StealthDetection.target_metadata() |> Map.put(:guid, character.object.guid)

    cond do
      StealthDetection.marked_by?(meta, character.object.guid) ->
        true

      Map.get(meta, :stealthed?, false) ->
        detects_stealth?(character, guid, detector, meta)

      true ->
        StealthDetection.detectable?(detector, meta, nil, Time.now())
    end
  end

  defp detects_stealth?(character, guid, detector, meta) do
    now = Time.now()

    case {World.position(character, now), World.position(guid, now)} do
      {{world, x, y, z}, {world, tx, ty, tz}} ->
        {_x, _y, _z, orientation} = character.movement_block.position
        behind? = Math.behind?({x, y, orientation}, {tx, ty})
        distance = Math.distance({x, y, z}, {tx, ty, tz})

        StealthDetection.detectable?(detector, meta, distance, now, behind?) and
          World.line_of_sight?(character, guid)

      _ ->
        false
    end
  end

  def sync_detection(state, previous, current) when previous == current, do: state

  def sync_detection(%{character: character} = state, _previous, _current) do
    notify_visibility_changed(character)
    resync_player(state)
  end

  defp owned_or_grouped?(viewer, target, meta) do
    Map.get(meta, :owner_guid) == viewer or
      case PartySystem.group_of(viewer) do
        %{members: members} -> Enum.any?(members, &(&1.guid == target))
        _ -> false
      end
  end

  defp corpse_distance(%{object: %{guid: viewer_guid}}, target_guid) do
    corpse_guid = Corpse.guid_for(viewer_guid)
    World.distance_between(corpse_guid, target_guid)
  end

  defp corpse_distance(_character, _target_guid), do: nil

  defp sync_visible_entities(%{tracked_entities: tracked} = state, self_guid, cells) do
    visible = visible_members(cells)

    visible_guids =
      visible
      |> Enum.filter(fn %{guid: guid} -> guid == self_guid or can_see?(state, guid) end)
      |> MapSet.new(& &1.guid)

    tracked = tracked || MapSet.new()

    tracked
    |> MapSet.difference(visible_guids)
    |> Enum.each(&send_destroy/1)

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

  defp sync_visibility_cells(state, _viewer_guid, old_cells, new_cells) when old_cells == new_cells, do: state

  defp sync_visibility_cells(state, viewer_guid, old_cells, new_cells) do
    removed_cells = MapSet.difference(old_cells, new_cells)
    added_cells = MapSet.difference(new_cells, old_cells)

    activate_cells(state, added_cells)
    Enum.each(removed_cells, &Group.demonitor(@group, cell_key(&1)))
    Enum.each(added_cells, &Group.monitor(@group, cell_key(&1)))

    state
    |> Map.put(:visibility_cells, new_cells)
    |> sync_visible_entities(viewer_guid, new_cells)
  end

  defp viewpoint_cells(%{viewpoint_guid: guid, character: %{internal: %{world: world}}})
       when is_integer(guid) and guid > 0 do
    case viewpoint_location(guid) do
      {^world, x, y, z} -> visible_cells_at(world, x, y, z)
      _missing -> nil
    end
  end

  defp viewpoint_cells(_state), do: nil

  defp put_viewpoint(%State{} = state, guid), do: %{state | viewpoint_guid: guid}
  defp put_viewpoint(state, guid), do: Map.put(state, :viewpoint_guid, guid)

  defp viewpoint_location(guid) do
    World.position(guid)
  end

  defp visible_cells_at(world, x, y, z) do
    world
    |> SpatialGrid.cells_in_range(x, y, z, @range)
    |> MapSet.new()
  end

  defp visible_members(cells) do
    cell_members =
      Enum.flat_map(cells, fn cell ->
        @group
        |> Group.members(cell_key(cell))
        |> Enum.map(fn {_pid, meta} -> meta end)
      end)

    (cell_members ++ pinned_transports(cells))
    |> Map.new(fn %{guid: guid} = meta -> {guid, meta} end)
    |> Map.values()
  end

  defp pinned_transports(cells) do
    case Enum.at(cells, 0) do
      {%WorldRef{} = world, _x, _y} ->
        world
        |> Transports.ships_on_world()
        |> Enum.map(&%{guid: &1.guid, type: :game_object})

      nil ->
        []
    end
  end

  defp track_joined(state, %{guid: guid} = meta) do
    state = add_to_entity_lists(state, meta)

    if tracked?(state, guid) or not can_see?(state, guid) do
      state
    else
      Entity.request_update_from(guid, state.guid)
      state
    end
  end

  defp track_left(state, guid, type) do
    state = remove_from_entity_lists(state, guid, type)

    if tracked?(state, guid) and not Transports.ship?(guid) and not currently_visible?(state, guid) do
      send_destroy(guid)
      untrack_entity(state, guid)
    else
      state
    end
  end

  defp send_destroy(guid) do
    Network.send_packet(%Message.SmsgDestroyObject{guid: guid}, self(), force: true)
  end

  defp currently_visible?(%{visibility_cells: cells}, guid) do
    if pinned_transport?(guid, cells) do
      true
    else
      case World.cell_for(guid) do
        nil -> false
        cell -> MapSet.member?(cells, cell)
      end
    end
  end

  defp currently_visible?(_state, _guid), do: false

  defp pinned_transport?(guid, cells) do
    case {Transports.get(guid), Enum.at(cells, 0)} do
      {%{route_kind: :ship, world: world}, {world, _x, _y}} -> true
      _ -> false
    end
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

  defp put_visibility_cell(%{internal: %Internal{} = internal} = entity, cell) do
    %{entity | internal: %{internal | visibility_cell: cell}}
  end

  defp activate_cells(%{cell_activator: nil}, _cells), do: :ok

  defp activate_cells(state, cells) do
    CellActivator.activate(cells, Map.get(state, :cell_activator, CellActivator))
  end
end
