defmodule ThistleTea.Game.Entity.Logic.Aura.Transition do
  @moduledoc """
  Owns aura holder changes, client slot assignment, derived projections, and
  cause-sensitive transition effects.
  """

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura.Change
  alias ThistleTea.Game.Entity.Logic.Aura.ControlSync
  alias ThistleTea.Game.Entity.Logic.Aura.ModifierSync
  alias ThistleTea.Game.Entity.Logic.Aura.MovementSync
  alias ThistleTea.Game.Entity.Logic.Aura.ObjectSync
  alias ThistleTea.Game.Entity.Logic.Aura.PlayerSync
  alias ThistleTea.Game.Entity.Logic.Aura.Script
  alias ThistleTea.Game.Entity.Logic.Aura.StealthSync
  alias ThistleTea.Game.Entity.Logic.Aura.UnitSync
  alias ThistleTea.Game.Entity.Logic.Aura.ViewpointSync
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Reputation, as: ReputationLogic
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cooldowns

  @causes Change.causes()

  @aura_interrupt_not_seated 0x40000
  @stand_state_sit 1

  @cat_form 1
  @feral_forms [1, 5, 8]
  @leader_of_the_pack 17_007
  @leader_of_the_pack_aura 24_932
  @furor_talents [17_056, 17_058, 17_059, 17_060, 17_061]
  @furor_energize 17_099
  @furor_rage 17_057

  @cast_breaking_controls [:mod_stun, :mod_fear, :mod_confuse]
  @tactical_mastery_scripts 831..835

  def run(%{unit: %Unit{} = unit} = entity, %Change{holders: desired, cause: cause, now: now})
      when is_list(desired) and cause in @causes and is_integer(now) do
    previous = if is_list(unit.auras), do: unit.auras, else: []

    if desired == previous do
      {entity, []}
    else
      holders = assign_slots(previous, desired)
      reconcile(entity, previous, holders, cause, now)
    end
  end

  defp reconcile(entity, previous, holders, cause, now) do
    {removed, touched} = diff(previous, holders)
    modifier_events = ModifierSync.events(previous, holders)

    entity =
      entity
      |> put_holders(holders)
      |> ObjectSync.sync()
      |> PlayerSync.sync()
      |> StealthSync.sync()

    {entity, application_events} = application_hooks(entity, touched, cause, now)
    {entity, cooldown_events} = cooldown_hooks(entity, removed, now)
    script_events = Script.after_remove(entity, removed, cause)
    {entity, control_events} = ControlSync.sync(entity, now)
    {entity, movement_events} = MovementSync.sync_movement_state(entity, now)
    viewpoint_events = ViewpointSync.events(previous, holders, entity_guid(entity))
    release_events = release_controlled_events(entity, removed)
    forced_reaction_events = forced_reaction_events(entity, previous, holders)

    events =
      modifier_events ++
        application_events ++
        cooldown_events ++
        script_events ++
        control_events ++
        viewpoint_events ++ release_events ++ movement_events ++ forced_reaction_events

    {Core.mark_broadcast_update(entity), events}
  end

  defp forced_reaction_events(%Character{} = character, previous, current) do
    previous_reactions = forced_reactions(previous)
    current_reactions = forced_reactions(current)

    if previous_reactions == current_reactions do
      []
    else
      changed_factions =
        previous_reactions
        |> Map.keys()
        |> Kernel.++(Map.keys(current_reactions))
        |> Enum.uniq()
        |> Enum.filter(&(Map.get(previous_reactions, &1) != Map.get(current_reactions, &1)))

      friendly_faction_ids =
        Enum.filter(changed_factions, &friendly_reaction?(character, current_reactions, &1))

      reactions = current_reactions |> Enum.sort() |> Enum.to_list()
      [Effects.forced_reactions_changed(reactions, friendly_faction_ids)]
    end
  end

  defp forced_reaction_events(_entity, _previous, _current), do: []

  defp forced_reactions(holders) do
    holders
    |> Enum.flat_map(fn %Holder{auras: auras} -> auras end)
    |> Enum.reduce(%{}, fn
      %Aura{type: :force_reaction, misc_value: faction_id, amount: rank}, reactions
      when is_integer(faction_id) and faction_id > 0 and is_integer(rank) and rank in 0..7 ->
        Map.put(reactions, faction_id, rank)

      _aura, reactions ->
        reactions
    end)
  end

  defp friendly_reaction?(character, current_reactions, faction_id) do
    rank =
      case Map.fetch(current_reactions, faction_id) do
        {:ok, forced_rank} -> forced_rank
        :error -> character.player.reputation.ranks |> Map.get(faction_id) |> ReputationLogic.rank_value()
      end

    is_integer(rank) and rank >= ReputationLogic.rank_value(:friendly)
  end

  defp put_holders(%{unit: %Unit{} = unit} = entity, holders) do
    %{entity | unit: UnitSync.sync_unit(%{unit | auras: holders})}
  end

  defp assign_slots(previous, desired) do
    desired
    |> Enum.map(&normalize_visibility/1)
    |> Enum.map_reduce([], fn %Holder{} = holder, assigned ->
      holder = assign_slot(holder, previous, assigned)
      {holder, [holder | assigned]}
    end)
    |> elem(0)
  end

  defp normalize_visibility(%Holder{spell: %Spell{} = spell} = holder) do
    if UnitSync.visible?(spell), do: holder, else: %{holder | slot: nil}
  end

  defp assign_slot(%Holder{} = holder, previous, assigned) do
    preferred =
      if valid_slot?(holder.slot, holder.negative?) do
        holder.slot
      else
        previous_slot(previous, holder)
      end

    slot =
      if valid_slot?(preferred, holder.negative?) and free_slot?(assigned, preferred) do
        preferred
      else
        UnitSync.display_slot(assigned, holder)
      end

    %{holder | slot: slot}
  end

  defp previous_slot(previous, %Holder{} = holder) do
    case Enum.find(previous, &(holder_key(&1) == holder_key(holder))) do
      %Holder{slot: slot} -> slot
      _holder -> nil
    end
  end

  defp valid_slot?(slot, false), do: is_integer(slot) and slot in 0..31
  defp valid_slot?(slot, true), do: is_integer(slot) and slot in 32..47

  defp free_slot?(holders, slot), do: Enum.all?(holders, &(&1.slot != slot))

  defp diff(previous, holders) do
    previous = indexed(previous)
    current = indexed(holders)
    current_by_key = Map.new(current)
    previous_by_key = Map.new(previous)

    removed =
      for {key, holder} <- previous,
          not Map.has_key?(current_by_key, key),
          do: holder

    touched =
      for {key, holder} <- current,
          Map.get(previous_by_key, key) != holder,
          do: holder

    {removed, touched}
  end

  defp indexed(holders) do
    {indexed, _counts} =
      Enum.map_reduce(holders, %{}, fn %Holder{} = holder, counts ->
        key = holder_key(holder)
        occurrence = Map.get(counts, key, 0)
        {{key, occurrence, holder}, Map.put(counts, key, occurrence + 1)}
      end)

    Enum.map(indexed, fn {key, occurrence, holder} -> {{key, occurrence}, holder} end)
  end

  defp holder_key(%Holder{spell: %Spell{id: id}, caster_guid: caster_guid}), do: {id, caster_guid}

  defp application_hooks(entity, touched, :applied, now) do
    {entity, immediate_events} =
      Enum.reduce(touched, {entity, []}, fn %Holder{} = holder, {current, events} ->
        {current, sit_events} =
          current
          |> maybe_reset_shapeshift_power(holder)
          |> maybe_heal_increased_health(holder)
          |> maybe_interrupt_casting(holder)
          |> maybe_sit(holder)

        {current, events ++ sit_events}
      end)

    duration_events = Enum.flat_map(touched, &applied_duration_events(entity, &1, now))
    shapeshift_events = Enum.flat_map(touched, &shapeshift_talent_events(entity, &1))
    {entity, immediate_events ++ duration_events ++ shapeshift_events}
  end

  defp application_hooks(entity, _touched, _cause, _now), do: {entity, []}

  defp cooldown_hooks(entity, [], _now), do: {entity, []}
  defp cooldown_hooks(entity, removed, now), do: Cooldowns.activate_on_event(entity, removed, now)

  defp applied_duration_events(%Character{}, %Holder{slot: slot, expires_at: expires_at}, now)
       when is_integer(slot) and is_integer(expires_at) and expires_at != -1 do
    [Effects.aura_duration(slot, max(expires_at - now, 0))]
  end

  defp applied_duration_events(_entity, _holder, _now), do: []

  defp shapeshift_talent_events(%{object: %{guid: guid}, unit: %Unit{} = unit} = entity, %Holder{} = holder) do
    case shapeshift_form_misc(holder) do
      form when form in @feral_forms ->
        leader_of_the_pack_events(entity, guid, unit.level) ++ furor_events(entity, guid, unit.level, form)

      form when is_integer(form) ->
        [Effects.remove_aura(guid, guid, @leader_of_the_pack_aura)]

      _no_form ->
        []
    end
  end

  defp shapeshift_form_misc(%Holder{auras: auras}) do
    Enum.find_value(auras, fn
      %Aura{type: :mod_shapeshift, misc_value: misc} when is_integer(misc) and misc > 0 -> misc
      _aura -> nil
    end)
  end

  defp leader_of_the_pack_events(entity, guid, level) do
    if holder_spell?(entity, @leader_of_the_pack) do
      [Effects.trigger_spell(guid, level || 1, guid, @leader_of_the_pack_aura)]
    else
      []
    end
  end

  defp furor_events(entity, guid, level, form) do
    chance = furor_chance(entity)

    if chance > 0 and :rand.uniform(100) <= chance do
      spell_id = if form == @cat_form, do: @furor_energize, else: @furor_rage
      [Effects.trigger_spell(guid, level || 1, guid, spell_id)]
    else
      []
    end
  end

  defp furor_chance(%{unit: %Unit{auras: holders}}) when is_list(holders) do
    Enum.find_value(holders, 0, fn
      %Holder{spell: %Spell{id: id}, auras: auras} when id in @furor_talents ->
        Enum.find_value(auras, fn
          %Aura{type: :dummy, amount: amount} when is_integer(amount) -> amount
          _aura -> nil
        end)

      _holder ->
        nil
    end)
  end

  defp furor_chance(_entity), do: 0

  defp holder_spell?(%{unit: %Unit{auras: holders}}, spell_id) when is_list(holders) do
    Enum.any?(holders, &match?(%Holder{spell: %Spell{id: ^spell_id}}, &1))
  end

  defp holder_spell?(_entity, _spell_id), do: false

  defp maybe_reset_shapeshift_power(%{unit: %Unit{} = unit} = entity, %Holder{} = holder) do
    cond do
      not Holder.has_aura_type?(holder, :mod_shapeshift) ->
        entity

      cat_form?(holder) and unit.class == 11 ->
        %{entity | unit: %{unit | power4: 0}}

      unit.power_type == 1 and is_integer(unit.power2) and unit.power2 > 0 ->
        %{entity | unit: %{unit | power2: min(unit.power2, retained_stance_rage(entity))}}

      true ->
        entity
    end
  end

  defp maybe_reset_shapeshift_power(entity, _holder), do: entity

  defp retained_stance_rage(entity) do
    entity.unit.auras
    |> Enum.flat_map(fn %Holder{auras: auras} -> auras end)
    |> Enum.reduce(0, fn
      %Aura{type: :override_class_scripts, misc_value: misc}, best when misc in @tactical_mastery_scripts ->
        max(best, (misc - 830) * 50)

      _aura, best ->
        best
    end)
  end

  defp cat_form?(%Holder{auras: auras}) do
    Enum.any?(auras, &match?(%Aura{type: :mod_shapeshift, misc_value: 1}, &1))
  end

  defp maybe_interrupt_casting(%{internal: %{casting: casting}} = entity, %Holder{} = holder)
       when not is_nil(casting) do
    cond do
      Holder.has_any_type?(holder, @cast_breaking_controls) -> clear_casting(entity)
      Holder.has_aura_type?(holder, :mod_silence) and silenceable_cast?(casting) -> clear_casting(entity)
      true -> entity
    end
  end

  defp maybe_interrupt_casting(entity, _holder), do: entity

  defp silenceable_cast?(%{spell: %Spell{prevention_type: 1}}), do: true
  defp silenceable_cast?(_casting), do: false

  defp clear_casting(%{internal: internal, unit: unit} = entity) do
    %{entity | internal: %{internal | casting: nil}, unit: %{unit | channel_spell: 0, channel_object: 0}}
  end

  defp maybe_heal_increased_health(entity, %Holder{auras: auras}) do
    auras
    |> Enum.reduce(0, fn
      %Aura{type: :mod_increase_health, amount: amount}, acc when is_integer(amount) and amount > 0 -> acc + amount
      _aura, acc -> acc
    end)
    |> case do
      0 -> entity
      amount -> Core.heal(entity, amount)
    end
  end

  defp maybe_sit(%{unit: %Unit{stand_state: stand_state} = unit} = entity, %Holder{spell: %Spell{} = spell}) do
    if (spell.aura_interrupt_flags &&& @aura_interrupt_not_seated) != 0 and stand_state != @stand_state_sit do
      {%{entity | unit: %{unit | stand_state: @stand_state_sit}}, [Effects.stand_state(@stand_state_sit)]}
    else
      {entity, []}
    end
  end

  defp maybe_sit(entity, _holder), do: {entity, []}

  defp release_controlled_events(%Character{object: %{guid: owner_guid}} = character, removed)
       when is_integer(owner_guid) do
    controlled_guid = Companion.control_guid(character)

    for %Holder{caster_guid: ^owner_guid, spell: %Spell{id: spell_id, effects: effects}} <- removed,
        is_integer(controlled_guid),
        Enum.any?(effects, &(&1.type == :summon_possessed)) do
      Effects.release_controlled(owner_guid, controlled_guid, spell_id)
    end
  end

  defp release_controlled_events(_entity, _removed), do: []

  defp entity_guid(%{object: %{guid: guid}}), do: guid
  defp entity_guid(_entity), do: nil
end
