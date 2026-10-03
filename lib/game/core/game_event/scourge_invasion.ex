defmodule ThistleTea.Game.Core.GameEvent.ScourgeInvasion do
  @moduledoc """
  The Scourge Invasion (vmangos `ScourgeInvasionEvent`, hardcoded game event
  17). Necropolises descend on Winterspring, Tanaris, Azshara, the Blasted
  Lands, the Eastern Plaguelands, and the Burning Steppes, each zone under
  the eye of a Mouth of Kel'Thuzad. A zone holds out until every necropolis
  over it falls; that victory is counted, and the zone stays clear for
  forty-five minutes to an hour before the Scourge may return, never twice in
  a row. The first wave strikes every zone at once; after the first victory a
  zone only falls under attack while no more than one other is. Fifty, a
  hundred, and a hundred and fifty victories open the Argent Dawn's
  milestones, and the last ends the invasion.

  The calendar never starts these events. `World.System.ScourgeInvasion`
  keeps the attack clock in vmangos's server variables and drives the zone
  and milestone events from them. `begin/3` is vmangos's `Enable`, which lets
  every zone that may be attacked fall at once, and `update/4` replays one
  twenty-second pass of its controller over the zones in order, so a zone
  started or defeated early in the pass counts toward the zones after it.
  """

  @behaviour ThistleTea.Game.Core.GameEvent.Rule

  alias ThistleTea.Game.Core.GameEvent.Rule
  alias ThistleTea.Game.Core.GameEvent.ScourgeInvasion.Zone
  alias ThistleTea.Game.Core.Rolls

  @invasion 17
  @fifty_victories 96
  @hundred_victories 97
  @hundred_fifty_victories 98
  @invasions_done 99
  @attack_count 17_000
  @last_attack_zone 17_001
  @battles_won_state 2219
  @fewest_attack_seconds 2_700
  @most_attack_seconds 3_600
  @last_victory 150

  @zones [
    %Zone{
      name: :winterspring,
      zone_id: 618,
      map_id: 1,
      event: 90,
      necropolises: 3,
      mouth: {7736.56, -4033.75, 696.327, 5.51524},
      attack_time_variable: 17_618,
      remaining_variable: 17_090,
      invaded_state: 2259,
      remaining_state: 2284
    },
    %Zone{
      name: :tanaris,
      zone_id: 440,
      map_id: 1,
      event: 91,
      necropolises: 3,
      mouth: {-8352.68, -3972.68, 10.0753, 2.14675},
      attack_time_variable: 17_440,
      remaining_variable: 17_091,
      invaded_state: 2263,
      remaining_state: 2283
    },
    %Zone{
      name: :azshara,
      zone_id: 16,
      map_id: 1,
      event: 92,
      necropolises: 2,
      mouth: {3273.75, -4276.98, 125.509, 5.44543},
      attack_time_variable: 17_016,
      remaining_variable: 17_092,
      invaded_state: 2260,
      remaining_state: 2279
    },
    %Zone{
      name: :blasted_lands,
      zone_id: 4,
      map_id: 0,
      event: 93,
      necropolises: 2,
      mouth: {-11_429.3, -3327.82, 7.73628, 1.0821},
      attack_time_variable: 17_004,
      remaining_variable: 17_093,
      invaded_state: 2261,
      remaining_state: 2280
    },
    %Zone{
      name: :eastern_plaguelands,
      zone_id: 139,
      map_id: 0,
      event: 94,
      necropolises: 2,
      mouth: {2014.55, -4934.52, 73.9846, 0.0698132},
      attack_time_variable: 17_139,
      remaining_variable: 17_094,
      invaded_state: 2264,
      remaining_state: 2282
    },
    %Zone{
      name: :burning_steppes,
      zone_id: 46,
      map_id: 0,
      event: 95,
      necropolises: 2,
      mouth: {-8229.53, -1118.11, 144.012, 6.17846},
      attack_time_variable: 17_046,
      remaining_variable: 17_095,
      invaded_state: 2262,
      remaining_state: 2281
    }
  ]

  @impl Rule
  def events,
    do:
      [@invasion | Enum.map(@zones, & &1.event)] ++
        [@fifty_victories, @hundred_victories, @hundred_fifty_victories, @invasions_done]

  @impl Rule
  def active_events(%DateTime{}, _scheduled), do: []

  @impl Rule
  def boundaries(%DateTime{}), do: []

  def invasion_event, do: @invasion

  def zones, do: @zones

  def zone(name) when is_atom(name), do: Enum.find(@zones, &(&1.name == name))

  def zone_for(zone_id) when is_integer(zone_id), do: Enum.find(@zones, &(&1.zone_id == zone_id))

  def variables,
    do: [@attack_count, @last_attack_zone | Enum.flat_map(@zones, &[&1.attack_time_variable, &1.remaining_variable])]

  def victories(variables) when is_map(variables), do: Map.get(variables, @attack_count, 0)

  def remaining(variables, %Zone{remaining_variable: variable}), do: Map.get(variables, variable, 0)

  def attack_time(variables, %Zone{attack_time_variable: variable}), do: Map.get(variables, variable, 0)

  def over?(variables), do: victories(variables) >= @last_victory

  def begin(variables, %MapSet{} = active, now) when is_map(variables) and is_integer(now) do
    {variables, active, actions} =
      Enum.reduce(@zones, {variables, active, []}, fn zone, {variables, active, actions} ->
        if zone.name not in active and may_attack?(variables, active, zone, now),
          do: {start(variables, zone), MapSet.put(active, zone.name), [{:start, zone} | actions]},
          else: {variables, active, actions}
      end)

    {variables, active, Enum.reverse(actions)}
  end

  def update(variables, %MapSet{} = active, now, %Rolls{} = rolls) when is_map(variables) and is_integer(now) do
    {variables, active, actions} =
      Enum.reduce(@zones, {variables, active, []}, fn zone, acc -> update_zone(zone, acc, now, rolls) end)

    {variables, active, Enum.reverse(actions)}
  end

  def start(variables, %Zone{} = zone), do: Map.put(variables, zone.remaining_variable, zone.necropolises)

  def necropolis_fell(variables, %Zone{} = zone),
    do: Map.put(variables, zone.remaining_variable, max(remaining(variables, zone) - 1, 0))

  def reset(variables, now) when is_integer(now) do
    Enum.reduce(@zones, variables, fn zone, variables ->
      variables |> Map.put(zone.attack_time_variable, now) |> Map.put(zone.remaining_variable, 0)
    end)
  end

  def driven(variables, %MapSet{} = active, enabled?) when is_map(variables) and is_boolean(enabled?) do
    victories = victories(variables)
    invading? = enabled? and victories < @last_victory
    done? = enabled? and victories >= @last_victory

    @zones
    |> Map.new(&{&1.event, invading? and &1.name in active})
    |> Map.merge(%{
      @invasion => invading?,
      @fifty_victories => invading? and victories >= 50 and victories < 100,
      @hundred_victories => invading? and victories >= 100,
      @hundred_fifty_victories => done?,
      @invasions_done => done?
    })
  end

  def world_states(variables) when is_map(variables) do
    zone_states =
      Enum.flat_map(@zones, fn zone ->
        remaining = remaining(variables, zone)
        [{zone.invaded_state, min(remaining, 1)}, {zone.remaining_state, remaining}]
      end)

    [{@battles_won_state, victories(variables)} | zone_states]
  end

  defp update_zone(%Zone{} = zone, {variables, active, actions}, now, rolls) do
    attack_at = now + Rolls.integer(rolls, :attack_delay, @fewest_attack_seconds, @most_attack_seconds)

    cond do
      zone.name not in active ->
        variables =
          if attack_time(variables, zone) < now and MapSet.size(active) > 1,
            do: Map.put(variables, zone.attack_time_variable, attack_at),
            else: variables

        if may_attack?(variables, active, zone, now),
          do: {start(variables, zone), MapSet.put(active, zone.name), [{:start, zone} | actions]},
          else: {variables, active, actions}

      attack_time(variables, zone) < now and remaining(variables, zone) == 0 ->
        variables =
          variables
          |> Map.put(zone.attack_time_variable, attack_at)
          |> Map.put(@attack_count, victories(variables) + 1)
          |> Map.put(@last_attack_zone, zone.zone_id)

        {variables, MapSet.delete(active, zone.name), [{:stop, zone} | actions]}

      true ->
        {variables, active, actions}
    end
  end

  defp may_attack?(variables, active, zone, now) do
    now >= attack_time(variables, zone) and zone.zone_id != Map.get(variables, @last_attack_zone, 0) and
      not (MapSet.size(active) > 1 and victories(variables) > 0)
  end
end
