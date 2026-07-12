defmodule ThistleTea.Game.Entity.Logic.AI.BT.Mob.Spells do
  @moduledoc """
  Spell-list casting subtree for mobs, following vmangos `creature_spells`
  semantics: per-spell timers rolled from initial delays on combat entry, one
  cast attempt per list tick, target resolution by cast-target type, and the
  main-ranged stance that holds a caster at range while its primary spell
  keeps succeeding.
  """
  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.CreatureSpell
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Spell, as: SpellBT
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Entity.Logic.Combat, as: CombatLogic
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Entity.Logic.Hostility
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastValidation
  alias ThistleTea.Game.Spell.Targets
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata

  @list_tick_ms 1_200
  @channel_wake_ms 50
  @unit_flag_in_combat 0x00080000
  @unit_flag_not_selectable 0x02000000
  @injured_default_radius 30.0
  @injured_default_threshold 50

  def list_tick_ms, do: @list_tick_ms

  def step do
    BT.sequence([
      BT.condition(&has_spells?/2),
      BT.action(&try_cast/2)
    ])
  end

  def hold_ranged_step do
    BT.sequence([
      BT.condition(&holding_ranged?/2),
      BT.action(&hold_ranged_wait/2)
    ])
  end

  def has_spells?(%Mob{internal: %Internal{creature: %Creature{spells: [_ | _]}}}, _blackboard), do: true
  def has_spells?(_state, _blackboard), do: false

  def holding_ranged?(%Mob{} = state, %Blackboard{} = blackboard) do
    has_spells?(state, blackboard) and not Blackboard.combat_movement?(blackboard)
  end

  def holding_ranged?(_state, _blackboard), do: false

  def next_spell_delay(%Mob{} = state, %Blackboard{} = blackboard, now) do
    if has_spells?(state, blackboard) do
      Blackboard.delay_until(blackboard, :next_spell_list_at, now)
    end
  end

  defp try_cast(%Mob{} = state, %Blackboard{} = blackboard) do
    try_cast(state, blackboard, Time.now())
  end

  def try_cast(%Mob{} = state, %Blackboard{} = blackboard, now) when is_integer(now) do
    spells = spell_entries(state)
    blackboard = ensure_spell_timers(blackboard, spells, now)

    if Blackboard.ready_for?(blackboard, :next_spell_list_at, now) do
      blackboard = Blackboard.put_next_at(blackboard, :next_spell_list_at, @list_tick_ms, now)
      attempt_ready_spells(state, blackboard, spells, now)
    else
      {:failure, state, blackboard}
    end
  end

  def hold_ranged_wait(%Mob{} = state, %Blackboard{} = blackboard) do
    hold_ranged_wait(state, blackboard, Time.now())
  end

  def hold_ranged_wait(%Mob{} = state, %Blackboard{} = blackboard, now) when is_integer(now) do
    state = halt_movement(state, now)
    delay_ms = max(Blackboard.delay_until(blackboard, :next_spell_list_at, now), 1)
    {BT.running(min(delay_ms, @list_tick_ms), :spell_list), state, blackboard}
  end

  defp spell_entries(%Mob{internal: %Internal{pet: %Pet{autocast: autocast}, creature: %Creature{spells: spells}}})
       when is_list(spells) do
    Enum.filter(spells, &MapSet.member?(autocast, &1.spell_id))
  end

  defp spell_entries(%Mob{internal: %Internal{creature: %Creature{spells: spells}}}) when is_list(spells) do
    spells
  end

  defp spell_entries(%Mob{}), do: []

  defp ensure_spell_timers(%Blackboard{} = blackboard, spells, now) do
    case Map.get(blackboard, :spell_timers) do
      timers when is_map(timers) ->
        blackboard

      _ ->
        Enum.reduce(Enum.with_index(spells), blackboard, fn {entry, index}, acc ->
          Blackboard.put_spell_timer(acc, index, CreatureSpell.roll_initial_delay_ms(entry), now)
        end)
    end
  end

  defp attempt_ready_spells(%Mob{} = state, %Blackboard{} = blackboard, spells, now) do
    spells
    |> Enum.with_index()
    |> Enum.reduce_while({:failure, state, blackboard}, fn {entry, index}, {_status, state, blackboard} ->
      attempt_if_ready(state, blackboard, entry, index, now)
    end)
  end

  defp attempt_if_ready(%Mob{} = state, %Blackboard{} = blackboard, entry, index, now) do
    if Blackboard.spell_timer_ready?(blackboard, index, now) do
      case attempt_cast(state, blackboard, entry, index, now) do
        {:cast, status, state, blackboard} -> {:halt, {status, state, blackboard}}
        {:skip, state, blackboard} -> {:cont, {:failure, state, blackboard}}
      end
    else
      {:cont, {:failure, state, blackboard}}
    end
  end

  def attempt_scripted_cast(%Mob{} = state, %Blackboard{} = blackboard, %CreatureSpell{} = entry, target_guid, now)
      when is_integer(now) do
    spell = lookup_spell(state, entry.spell_id)

    with true <- is_integer(target_guid) and not is_nil(spell),
         true <- flags_allow?(state, entry, target_guid),
         {:ok, state} <- release_previous_cast(state, entry),
         targets = Targets.unit(target_guid),
         :ok <- CastValidation.validate(state, spell, targets, build_target_info(state, target_guid), now) do
      {scripted_cast(state, spell, targets, target_guid, now), blackboard}
    else
      _ -> {state, blackboard}
    end
  end

  defp release_previous_cast(%Mob{internal: %Internal{casting: nil}} = state, _entry), do: {:ok, state}

  defp release_previous_cast(%Mob{} = state, %CreatureSpell{} = entry) do
    if CreatureSpell.flag?(entry, :interrupt_previous) do
      {:ok, SpellBT.clear_cast(state)}
    else
      :busy
    end
  end

  defp scripted_cast(%Mob{} = state, %Spell{} = spell, targets, target_guid, now) do
    state =
      state
      |> prepare_to_cast(spell, target_guid, now)
      |> Event.enqueue(Event.spell_start(state.object.guid, spell.id, spell.cast_time_ms || 0, targets.raw))
      |> SpellBT.start_cast(spell, targets, now)

    finish_if_instant(state, spell, now)
  end

  defp finish_if_instant(%Mob{internal: %Internal{casting: nil}} = state, _spell, _now), do: state

  defp finish_if_instant(%Mob{} = state, %Spell{} = spell, now) do
    if (spell.cast_time_ms || 0) == 0 and not Spell.attribute?(spell, :channeled) do
      SpellBT.complete_cast(state, now)
    else
      state
    end
  end

  defp attempt_cast(%Mob{} = state, %Blackboard{} = blackboard, %CreatureSpell{} = entry, index, now) do
    spell = lookup_spell(state, entry.spell_id)
    target_guid = resolve_target(state, entry, spell)

    cond do
      is_nil(spell) or is_nil(target_guid) ->
        {:skip, state, blackboard}

      not flags_allow?(state, entry, target_guid) ->
        {:skip, state, blackboard}

      true ->
        validate_and_cast(state, blackboard, entry, index, spell, target_guid, now)
    end
  end

  defp validate_and_cast(%Mob{} = state, %Blackboard{} = blackboard, entry, index, spell, target_guid, now) do
    targets = Targets.unit(target_guid)

    case CastValidation.validate(state, spell, targets, build_target_info(state, target_guid), now) do
      :ok ->
        if probability_passes?(entry) do
          start_spell_cast(state, blackboard, entry, index, spell, targets, target_guid, now)
        else
          blackboard =
            blackboard
            |> Blackboard.put_spell_timer(index, CreatureSpell.roll_repeat_delay_ms(entry), now)
            |> maybe_resume_movement(entry)

          {:skip, state, blackboard}
        end

      {:error, _reason} ->
        {:skip, state, maybe_resume_movement(blackboard, entry)}
    end
  end

  defp start_spell_cast(%Mob{} = state, %Blackboard{} = blackboard, entry, index, spell, targets, target_guid, now) do
    blackboard = Blackboard.put_spell_timer(blackboard, index, CreatureSpell.roll_repeat_delay_ms(entry), now)
    {state, blackboard} = maybe_hold_ranged(state, blackboard, entry)

    state =
      state
      |> prepare_to_cast(spell, target_guid, now)
      |> Event.enqueue(Event.spell_start(state.object.guid, spell.id, spell.cast_time_ms || 0, targets.raw))
      |> SpellBT.start_cast(spell, targets, now)

    finish_or_schedule(state, blackboard, spell, now)
  end

  defp finish_or_schedule(%Mob{internal: %Internal{casting: nil}} = state, blackboard, _spell, _now) do
    {:cast, :failure, state, blackboard}
  end

  defp finish_or_schedule(%Mob{} = state, blackboard, %Spell{} = spell, now) do
    if (spell.cast_time_ms || 0) == 0 and not Spell.attribute?(spell, :channeled) do
      {:cast, :failure, SpellBT.complete_cast(state, now), blackboard}
    else
      {:cast, BT.running(cast_wake_delay(spell), :casting), state, blackboard}
    end
  end

  defp cast_wake_delay(%Spell{cast_time_ms: cast_time_ms}) when is_integer(cast_time_ms) and cast_time_ms > 0 do
    cast_time_ms
  end

  defp cast_wake_delay(_spell), do: @channel_wake_ms

  defp prepare_to_cast(%Mob{} = state, %Spell{} = spell, target_guid, now) do
    if (spell.cast_time_ms || 0) > 0 or Spell.attribute?(spell, :channeled) do
      state
      |> halt_movement(now)
      |> face_target(target_guid)
    else
      state
    end
  end

  defp halt_movement(%Mob{} = state, now) do
    if Movement.moving?(state, now) do
      state
      |> Movement.halt(now)
      |> Event.enqueue(Event.movement_stopped())
    else
      state
    end
  end

  defp face_target(%Mob{object: %{guid: guid}} = state, target_guid) when target_guid != guid do
    case World.target_position(target_guid) do
      {map, tx, ty, _tz} when map == state.internal.map ->
        set_orientation_towards(state, {tx, ty})

      _ ->
        state
    end
  end

  defp face_target(%Mob{} = state, _target_guid), do: state

  defp set_orientation_towards(
         %Mob{movement_block: %MovementBlock{position: {mx, my, mz, _o}} = movement_block} = state,
         {tx, ty}
       ) do
    orientation = :math.atan2(ty - my, tx - mx)
    %{state | movement_block: %{movement_block | position: {mx, my, mz, orientation}}}
  end

  defp set_orientation_towards(%Mob{} = state, _target), do: state

  defp lookup_spell(%Mob{internal: %Internal{spellbook: spellbook}}, spell_id) when is_map(spellbook) do
    Map.get(spellbook, spell_id)
  end

  defp lookup_spell(_state, _spell_id), do: nil

  def resolve_target(%Mob{object: %{guid: guid}}, %CreatureSpell{cast_target: :self}, _spell) do
    guid
  end

  def resolve_target(%Mob{unit: %Unit{target: target}}, %CreatureSpell{cast_target: cast_target}, _spell)
      when cast_target in [
             :victim,
             :hostile_second_aggro,
             :hostile_last_aggro,
             :hostile_random,
             :hostile_random_not_top
           ] and is_integer(target) and target > 0 do
    target
  end

  def resolve_target(%Mob{} = state, %CreatureSpell{cast_target: :friendly_injured} = entry, spell) do
    find_injured_friendly(state, entry, spell, nil)
  end

  def resolve_target(
        %Mob{object: %{guid: guid}} = state,
        %CreatureSpell{cast_target: :friendly_injured_except} = entry,
        spell
      ) do
    find_injured_friendly(state, entry, spell, guid)
  end

  def resolve_target(
        %Mob{object: %{guid: guid}} = state,
        %CreatureSpell{cast_target: :friendly_missing_buff} = entry,
        _spell
      ) do
    if !AuraLogic.has_spell?(state, missing_buff_spell_id(entry)), do: guid
  end

  def resolve_target(_state, _entry, _spell), do: nil

  defp find_injured_friendly(%Mob{object: %{guid: guid}} = state, %CreatureSpell{} = entry, spell, except_guid) do
    radius = injured_search_radius(entry, spell)
    threshold = injured_threshold(entry)

    candidates =
      self_injured_candidate(state, threshold, except_guid) ++
        nearby_injured_candidates(state, radius, threshold, except_guid || guid)

    case Enum.max_by(candidates, fn {_guid, missing_pct} -> missing_pct end, fn -> nil end) do
      {target_guid, _missing_pct} -> target_guid
      nil -> nil
    end
  end

  defp self_injured_candidate(%Mob{object: %{guid: guid}} = state, threshold, except_guid) do
    missing_pct = 100 - Core.health_pct(state)

    if guid != except_guid and missing_pct > threshold and not Core.dead?(state) do
      [{guid, missing_pct}]
    else
      []
    end
  end

  defp nearby_injured_candidates(%Mob{} = state, radius, threshold, self_guid) do
    (World.nearby_mobs(state, radius) ++ World.nearby_players(state, radius))
    |> Enum.flat_map(fn {candidate_guid, _distance} ->
      case injured_friendly_missing_pct(state, candidate_guid, threshold) do
        missing_pct when is_number(missing_pct) and candidate_guid != self_guid -> [{candidate_guid, missing_pct}]
        _ -> []
      end
    end)
  end

  defp injured_friendly_missing_pct(%Mob{} = state, candidate_guid, threshold) do
    with %{alive?: true} = metadata <-
           Metadata.query(candidate_guid, [:alive?, :faction_template, :unit_flags, :health_pct]),
         true <- injured_candidate_flags_allow?(metadata),
         true <- Hostility.friendly?(state, metadata),
         missing_pct when is_number(missing_pct) and missing_pct > threshold <- missing_health_pct(metadata) do
      missing_pct
    else
      _ -> nil
    end
  end

  defp injured_candidate_flags_allow?(%{unit_flags: flags}) when is_integer(flags) do
    (flags &&& @unit_flag_in_combat) != 0 and (flags &&& @unit_flag_not_selectable) == 0
  end

  defp injured_candidate_flags_allow?(_metadata), do: false

  defp missing_health_pct(%{health_pct: health_pct}) when is_number(health_pct), do: 100 - health_pct
  defp missing_health_pct(_metadata), do: nil

  defp injured_search_radius(%CreatureSpell{target_param1: param1}, _spell) when is_number(param1) and param1 > 0 do
    param1 * 1.0
  end

  defp injured_search_radius(_entry, %Spell{range_yards: range}) when is_number(range) and range > 0 do
    range
  end

  defp injured_search_radius(_entry, _spell), do: @injured_default_radius

  defp injured_threshold(%CreatureSpell{target_param2: param2}) when is_integer(param2) and param2 in 1..100 do
    param2
  end

  defp injured_threshold(_entry), do: @injured_default_threshold

  defp missing_buff_spell_id(%CreatureSpell{target_param2: param2}) when is_integer(param2) and param2 > 0 do
    param2
  end

  defp missing_buff_spell_id(%CreatureSpell{spell_id: spell_id}), do: spell_id

  def flags_allow?(%Mob{object: %{guid: guid}} = state, %CreatureSpell{} = entry, target_guid) do
    cond do
      CreatureSpell.flag?(entry, :target_unreachable) ->
        false

      CreatureSpell.flag?(entry, :target_casting) ->
        false

      CreatureSpell.flag?(entry, :aura_not_present) and target_guid == guid ->
        not AuraLogic.has_spell?(state, entry.spell_id)

      CreatureSpell.flag?(entry, :only_in_melee) ->
        in_melee_range?(state, target_guid)

      CreatureSpell.flag?(entry, :not_in_melee) ->
        not in_melee_range?(state, target_guid)

      true ->
        true
    end
  end

  defp in_melee_range?(%Mob{object: %{guid: guid}}, target_guid) when target_guid == guid, do: false

  defp in_melee_range?(%Mob{} = state, target_guid) do
    case World.distance_to_guid(state, target_guid) do
      distance when is_number(distance) ->
        distance <= CombatLogic.melee_reach(own_combat_reach(state), target_combat_reach(target_guid))

      _ ->
        false
    end
  end

  defp own_combat_reach(%Mob{unit: %Unit{combat_reach: reach}}) when is_number(reach) and reach > 0, do: reach
  defp own_combat_reach(%Mob{}), do: Unit.default_combat_reach()

  defp target_combat_reach(target_guid) when is_integer(target_guid) do
    case Metadata.query(target_guid, [:combat_reach]) do
      %{combat_reach: combat_reach} when is_number(combat_reach) and combat_reach > 0 -> combat_reach
      _ -> Unit.default_combat_reach()
    end
  end

  defp target_combat_reach(_target_guid), do: Unit.default_combat_reach()

  defp build_target_info(%Mob{object: %{guid: guid}}, target_guid) when target_guid == guid, do: :self

  defp build_target_info(%Mob{} = state, target_guid) do
    case Metadata.query(target_guid, [:alive?, :faction_template, :unit_flags, :creature_type]) do
      nil ->
        :unknown

      metadata ->
        %{
          guid: target_guid,
          alive?: Map.get(metadata, :alive?, true),
          hostile?: Hostility.hostile?(state, metadata),
          friendly?: Hostility.friendly?(state, metadata),
          attackable?: Hostility.attackable?(state, target_guid),
          creature_type: Map.get(metadata, :creature_type),
          position: World.position(target_guid),
          los?: World.line_of_sight?(state, target_guid)
        }
    end
  end

  defp probability_passes?(%CreatureSpell{probability: probability})
       when is_integer(probability) and probability < 100 do
    :rand.uniform(100) <= probability
  end

  defp probability_passes?(_entry), do: true

  defp maybe_hold_ranged(%Mob{} = state, %Blackboard{} = blackboard, %CreatureSpell{} = entry) do
    if CreatureSpell.flag?(entry, :main_ranged) and Blackboard.combat_movement?(blackboard) do
      blackboard =
        blackboard
        |> Blackboard.set_combat_movement(false)
        |> Blackboard.clear_attack_started()

      {enqueue_attack_stop(state), blackboard}
    else
      {state, blackboard}
    end
  end

  defp enqueue_attack_stop(%Mob{object: %{guid: guid}, unit: %Unit{target: target}} = state)
       when is_integer(target) and target > 0 do
    Event.enqueue(state, Event.attack_stop(guid, target))
  end

  defp enqueue_attack_stop(%Mob{} = state), do: state

  defp maybe_resume_movement(%Blackboard{} = blackboard, %CreatureSpell{} = entry) do
    if CreatureSpell.flag?(entry, :main_ranged) do
      Blackboard.set_combat_movement(blackboard, true)
    else
      blackboard
    end
  end
end
