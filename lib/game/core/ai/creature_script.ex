defmodule ThistleTea.Game.Core.AI.CreatureScript do
  @moduledoc """
  Ports of vmangos C++ creature AIs, the `script_name` scripts, written as
  EventAI events so a scripted creature runs through the same event and
  script interpreter as its database-driven peers.

  In vmangos a script name takes priority over EventAI, so a ported creature's
  `creature_ai_events` rows are replaced, not extended. Talk steps carry
  broadcast text ids in `dataint`; the loader resolves them the same way it
  resolves database script talk steps. Like vmangos, EventAI runs an event's
  actions directly and ignores step delays, so `timed/1` wraps a delayed
  sequence in a `start_script` step, the way the database chains generic
  scripts. A C++ AI puts its creature back on its own faction in `Reset` when
  it respawns, so ports change factions with `faction/1`, which restores on
  respawn. A script whose creature reacts to a quest being accepted, as
  vmangos `QuestAccept` hooks do, returns the steps to append to that quest's
  start script from `quest_start_steps/0`, and one that reacts to a quest
  being turned in, as `QuestRewarded` hooks do, returns the steps to append
  to its completion script from `quest_end_steps/0`. A script that only
  reacts to quests claims no entries, so its creature keeps its EventAI.
  A creature that walks a path, as `npc_escortAI` creatures walk their
  `script_waypoint` rows, gets it and the steps to run at each of its points
  from `routes/0` (`CreatureScript.Route`); `start_waypoints` source 5
  starts it. `pick/1` runs one of several step lists at random, as C++
  scripts roll `urand`, nesting `start_script` choices four at a time, and
  `pick_weighted/1` does the same over `{weight, steps}` pairs. A creature
  whose C++ script builds its gossip menu in code gets it from `gossip/0`
  (`CreatureScript.Gossip`), and it replaces the database menu.
  """

  alias ThistleTea.Game.Core.AI.AIEvent
  alias ThistleTea.Game.Core.AI.CreatureScript.ArchmageTervosh
  alias ThistleTea.Game.Core.AI.CreatureScript.Bartleby
  alias ThistleTea.Game.Core.AI.CreatureScript.CapturedFelwoodOoze
  alias ThistleTea.Game.Core.AI.CreatureScript.ChickenCluck
  alias ThistleTea.Game.Core.AI.CreatureScript.CombatGadgets
  alias ThistleTea.Game.Core.AI.CreatureScript.DaphneStilwell
  alias ThistleTea.Game.Core.AI.CreatureScript.DashelStonefist
  alias ThistleTea.Game.Core.AI.CreatureScript.DragonsOfNightmare
  alias ThistleTea.Game.Core.AI.CreatureScript.ElementalInvaders
  alias ThistleTea.Game.Core.AI.CreatureScript.Eranikus
  alias ThistleTea.Game.Core.AI.CreatureScript.ErisHavenfire
  alias ThistleTea.Game.Core.AI.CreatureScript.Faulk
  alias ThistleTea.Game.Core.AI.CreatureScript.FelwoodOoze
  alias ThistleTea.Game.Core.AI.CreatureScript.GizeltonCaravan
  alias ThistleTea.Game.Core.AI.CreatureScript.Gossip
  alias ThistleTea.Game.Core.AI.CreatureScript.KindalMoonweaver
  alias ThistleTea.Game.Core.AI.CreatureScript.LazyPeon
  alias ThistleTea.Game.Core.AI.CreatureScript.MagramiSpectre
  alias ThistleTea.Game.Core.AI.CreatureScript.MajordomoExecutus
  alias ThistleTea.Game.Core.AI.CreatureScript.Murkdeep
  alias ThistleTea.Game.Core.AI.CreatureScript.Obsidion
  alias ThistleTea.Game.Core.AI.CreatureScript.Omen
  alias ThistleTea.Game.Core.AI.CreatureScript.Onyxia
  alias ThistleTea.Game.Core.AI.CreatureScript.Piznik
  alias ThistleTea.Game.Core.AI.CreatureScript.RabidThistleBear
  alias ThistleTea.Game.Core.AI.CreatureScript.Ragnaros
  alias ThistleTea.Game.Core.AI.CreatureScript.RiggleBassbait
  alias ThistleTea.Game.Core.AI.CreatureScript.Route
  alias ThistleTea.Game.Core.AI.CreatureScript.ScarletMonastery
  alias ThistleTea.Game.Core.AI.CreatureScript.Scholomance
  alias ThistleTea.Game.Core.AI.CreatureScript.ScourgeInvasion
  alias ThistleTea.Game.Core.AI.CreatureScript.ShakesOBreen
  alias ThistleTea.Game.Core.AI.CreatureScript.SicklyCritter
  alias ThistleTea.Game.Core.AI.CreatureScript.StaveOfTheAncients
  alias ThistleTea.Game.Core.AI.CreatureScript.StormwindRendezvous
  alias ThistleTea.Game.Core.AI.CreatureScript.TapokeSlimJahn
  alias ThistleTea.Game.Core.AI.CreatureScript.TestOfEndurance
  alias ThistleTea.Game.Core.AI.CreatureScript.Triage
  alias ThistleTea.Game.Core.AI.CreatureScript.TwiggyFlathead
  alias ThistleTea.Game.Core.AI.CreatureScript.TwilightCorrupter
  alias ThistleTea.Game.Core.AI.CreatureScript.WesternPlaguelands
  alias ThistleTea.Game.Core.AI.CreatureScript.WitchDoctorUnbagwa
  alias ThistleTea.Game.Core.AI.CreatureScript.Yenniku
  alias ThistleTea.Game.Core.AI.CreatureScript.ZulFarrak
  alias ThistleTea.Game.Core.AI.Script
  alias ThistleTea.Game.Core.AI.ScriptStep

  @callback entries() :: [pos_integer()]
  @callback events(pos_integer()) :: [%AIEvent{}]
  @callback quest_start_steps() :: %{pos_integer() => [%ScriptStep{}]}
  @callback quest_end_steps() :: %{pos_integer() => [%ScriptStep{}]}

  @callback routes() :: [%Route{}]
  @callback gossip() :: %{pos_integer() => %Gossip{}}

  @optional_callbacks quest_start_steps: 0, quest_end_steps: 0, routes: 0, gossip: 0

  @scripts [
    ArchmageTervosh,
    Bartleby,
    CapturedFelwoodOoze,
    ChickenCluck,
    CombatGadgets,
    DaphneStilwell,
    DashelStonefist,
    DragonsOfNightmare,
    ElementalInvaders,
    Eranikus,
    ErisHavenfire,
    Faulk,
    FelwoodOoze,
    GizeltonCaravan,
    LazyPeon,
    MagramiSpectre,
    MajordomoExecutus,
    Murkdeep,
    Obsidion,
    Omen,
    Onyxia,
    Piznik,
    RabidThistleBear,
    Ragnaros,
    RiggleBassbait,
    ScarletMonastery,
    Scholomance,
    ScourgeInvasion,
    ShakesOBreen,
    SicklyCritter,
    StaveOfTheAncients,
    StormwindRendezvous,
    KindalMoonweaver,
    TapokeSlimJahn,
    TestOfEndurance,
    Triage,
    TwiggyFlathead,
    TwilightCorrupter,
    WesternPlaguelands,
    WitchDoctorUnbagwa,
    Yenniku,
    ZulFarrak
  ]
  @timed_script 1
  @restore_on_respawn 0x01
  @start_script_options [
    {:datalong, :dataint},
    {:datalong2, :dataint2},
    {:datalong3, :dataint3},
    {:datalong4, :dataint4}
  ]

  def ported?(entry), do: not is_nil(script(entry))

  def events(entry) do
    case script(entry) do
      nil -> []
      script -> script.events(entry)
    end
  end

  def entries, do: Enum.flat_map(@scripts, & &1.entries())

  def creature_entries, do: Script.creature_entries(steps() ++ all_quest_steps())

  def summon_entries, do: Script.summon_entries(steps() ++ all_quest_steps())

  defp all_quest_steps, do: Enum.flat_map(Map.values(quest_start_steps()) ++ Map.values(quest_end_steps()), & &1)

  def quest_start_steps, do: quest_steps(:quest_start_steps)

  def quest_end_steps, do: quest_steps(:quest_end_steps)

  def routes, do: Enum.concat(implementations(:routes))

  def gossip, do: :gossip |> implementations() |> Enum.reduce(%{}, &Map.merge(&2, &1))

  defp quest_steps(callback) do
    callback
    |> implementations()
    |> Enum.reduce(%{}, &Map.merge(&2, &1, fn _quest_id, steps, more -> steps ++ more end))
  end

  defp implementations(callback) do
    @scripts
    |> Enum.filter(&(Code.ensure_loaded?(&1) and function_exported?(&1, callback, 0)))
    |> Enum.map(&apply(&1, callback, []))
  end

  defp steps do
    route_steps = routes() |> Enum.flat_map(&Map.values(&1.points)) |> List.flatten()
    gossip_steps = gossip() |> Map.values() |> Enum.flat_map(& &1.options) |> Enum.flat_map(& &1.steps)
    (entries() |> Enum.flat_map(&events/1) |> Enum.flat_map(&List.flatten(&1.actions))) ++ route_steps ++ gossip_steps
  end

  def event(entry, index, event_type, steps, opts \\ []) when is_integer(entry) and is_list(steps) do
    struct!(
      %AIEvent{id: entry * 100 + index, event_type: event_type, repeatable?: true, actions: [steps]},
      opts
    )
  end

  def timed(steps) when is_list(steps) do
    %ScriptStep{command: :start_script, datalong: @timed_script, dataint: 100, sub_scripts: %{@timed_script => steps}}
  end

  def pick([_ | _] = choices), do: choices |> Enum.map(&{1, &1}) |> choose()

  def pick_weighted([{weight, _steps} | _] = choices) when is_integer(weight), do: choose(choices)

  defp choose([{_weight, steps}]), do: steps

  defp choose(options) when length(options) > length(@start_script_options) do
    options
    |> Enum.chunk_every(ceil(length(options) / length(@start_script_options)))
    |> Enum.map(fn group -> {group |> Enum.map(&elem(&1, 0)) |> Enum.sum(), choose(group)} end)
    |> choose()
  end

  defp choose(options) do
    total = options |> Enum.map(&elem(&1, 0)) |> Enum.sum()
    chances = Enum.map(options, fn {weight, _steps} -> div(weight * 100, total) end)
    chances = List.update_at(chances, -1, &(&1 + 100 - Enum.sum(chances)))
    scripts = options |> Enum.with_index(1) |> Map.new(fn {{_weight, steps}, id} -> {id, steps} end)

    step =
      [@start_script_options, Enum.to_list(1..length(options)), chances]
      |> Enum.zip()
      |> Enum.reduce(%ScriptStep{command: :start_script, sub_scripts: scripts}, &put_option/2)

    [step]
  end

  defp put_option({{id_field, chance_field}, id, chance}, step),
    do: struct!(step, [{id_field, id}, {chance_field, chance}])

  def faction(faction_id) when is_integer(faction_id),
    do: %ScriptStep{command: :set_faction, datalong: faction_id, datalong2: @restore_on_respawn}

  def only_in_phases(phases) when is_list(phases) do
    Enum.reduce(0..31, 0, fn phase, mask ->
      if phase in phases, do: mask, else: Bitwise.bor(mask, Bitwise.bsl(1, phase))
    end)
  end

  defp script(entry), do: Enum.find(@scripts, &(entry in &1.entries()))
end
