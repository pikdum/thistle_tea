defmodule ThistleTea.Game.Player.OutdoorPvp do
  @moduledoc "Player-owned resource delivery, zone projections, and carrier lifecycle cleanup."

  alias ThistleTea.Game.Battleground
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Silithyst
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.OutdoorPvp.Plaguelands
  alias ThistleTea.Game.Player.Quests
  alias ThistleTea.Game.Player.Rest
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Pathfinding
  alias ThistleTea.Game.World.System.OutdoorPvp, as: OutdoorPvpSystem

  def refresh(%{ready: true, character: %Character{} = character} = state) do
    {x, y, z, _orientation} = character.movement_block.position

    zone =
      case Pathfinding.get_zone_and_area(character.internal.world.map_id, {x, y, z}) do
        {zone, _area} -> zone
        _ -> Rest.default_zone(character.internal.world.map_id)
      end

    refresh(state, zone)
  end

  def refresh(state), do: state

  def update_zone(state, zone, options \\ [])

  def update_zone(%State{ready: true, character: %Character{} = character} = state, zone, options) do
    if state.outdoor_pvp_key == {character.internal.world, zone}, do: state, else: refresh(state, zone, options)
  end

  def update_zone(state, _zone, _options), do: state

  def refresh(%State{character: %Character{} = character} = state, zone, options \\ []) do
    team = Battleground.team_for_race(character.unit.race)

    context =
      OutdoorPvpSystem.sync(
        state.guid,
        character.internal.world,
        zone,
        team,
        Keyword.get(options, :server, OutdoorPvpSystem)
      )

    project(context.states)

    %{
      state
      | outdoor_pvp_key: {character.internal.world, zone},
        outdoor_pvp_token: context.token,
        outdoor_pvp_favor?: context.favor?,
        outdoor_pvp_tower_buff: context.tower_buff
    }
    |> reconcile(options)
  end

  def update(%State{ready: true, pending_worldport?: false, outdoor_pvp_token: token} = state, token, states, buff)
      when is_reference(token) do
    project(states)
    reconcile(%{state | outdoor_pvp_tower_buff: buff})
  end

  def update(state, _token, _states, _buff), do: state

  def credit(%State{ready: true, pending_worldport?: false, outdoor_pvp_token: token} = state, token, entry)
      when is_reference(token), do: Quests.credit_kill_entry(state, entry, 0)

  def credit(state, _token, _entry), do: state

  def reconcile(state, options \\ [])

  def reconcile(%State{ready: true, character: %Character{} = character} = state, options) do
    now = Keyword.get_lazy(options, :now, &Time.now/0)
    lookup = Keyword.get(options, :spell_lookup, &SpellLoader.cached/1)

    wanted =
      if state.outdoor_pvp_favor?,
        do: [Silithyst.favor_spell(), state.outdoor_pvp_tower_buff],
        else: [state.outdoor_pvp_tower_buff]

    wanted = if Death.alive?(character), do: Enum.reject(wanted, &is_nil/1), else: []
    {character, effects} = Aura.remove_spells(character, managed_buffs() -- wanted, now)
    character = EventSink.emit(character, effects)

    character = Enum.reduce(wanted, character, &apply_buff(&2, &1, lookup, now))

    %{state | character: character}
  end

  def reconcile(state, _options), do: state

  def area_trigger(%{character: %Character{} = character} = state, trigger_id) do
    case Silithyst.turn_in(character, trigger_id, Time.now()) do
      {:ok, updated, team, token, effects} ->
        OutdoorPvpSystem.sync(state.guid, character.internal.world, 1377, team)

        case OutdoorPvpSystem.contribute(state.guid, character.internal.world, team, token) do
          {:ok, _outcome} ->
            state = %{state | character: EventSink.emit(updated, effects)}
            Quests.credit_kill_entry(state, Silithyst.credit_entry(team), 0)

          {:error, _reason} ->
            state
        end

      :unavailable ->
        state
    end
  end

  def leave(%State{character: %Character{} = character} = state) do
    OutdoorPvpSystem.leave(state.guid)

    {character, effects} =
      Aura.remove_spells(character, [Silithyst.carrier_spell() | managed_buffs()], Time.now())

    %{
      state
      | character: EventSink.emit(character, effects),
        outdoor_pvp_key: nil,
        outdoor_pvp_token: nil,
        outdoor_pvp_favor?: false,
        outdoor_pvp_tower_buff: nil
    }
  end

  def leave(state), do: state

  defp apply_buff(character, id, lookup, now) do
    with false <- Aura.has_spell?(character, id),
         %Spell{} = spell <- lookup.(id) do
      {character, effects} = Aura.apply_spell(character, character.object.guid, character.unit.level || 1, spell, now)
      EventSink.emit(character, effects)
    else
      _unchanged -> character
    end
  end

  defp managed_buffs, do: [Silithyst.favor_spell() | Plaguelands.buffs()]

  defp project(states),
    do:
      Enum.each(states, fn {id, value} ->
        Network.send_packet(%Message.SmsgUpdateWorldState{state: id, value: value})
      end)
end
