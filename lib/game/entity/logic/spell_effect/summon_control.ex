defmodule ThistleTea.Game.Entity.Logic.SpellEffect.SummonControl do
  @moduledoc false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.AI.BT.Combat, as: BTCombat
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Pet
  alias ThistleTea.Game.Entity.Logic.PlayerCombat
  alias ThistleTea.Game.Entity.Logic.Rogue
  alias ThistleTea.Game.Entity.Logic.SpellEffect.Amount
  alias ThistleTea.Game.Entity.Logic.Threat
  alias ThistleTea.Game.Entity.Logic.Warlock
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Cooldowns
  alias ThistleTea.Game.Spell.Effect

  def apply(
        %Character{
          object: %{guid: target_guid},
          movement_block: %{position: {target_x, target_y, _target_z, _target_o}}
        } = state,
        %CastContext{
          caster_guid: caster_guid,
          caster_level: caster_level,
          caster_type: :player,
          caster_position: {world, caster_x, caster_y, caster_z},
          caster_orientation: orientation
        },
        _spell,
        %Effect{type: :duel, misc_value: entry},
        _now
      )
      when is_integer(entry) and entry > 0 and target_guid != caster_guid do
    flag_position = {world, (caster_x + target_x) / 2, (caster_y + target_y) / 2, caster_z}

    {state,
     [
       Effects.duel_request(
         caster_guid,
         caster_level,
         target_guid,
         entry,
         flag_position,
         orientation
       )
     ]}
  end

  def apply(
        state,
        %CastContext{caster_guid: caster_guid},
        %Spell{id: spell_id},
        %Effect{type: :summon_pet, misc_value: entry},
        _now
      )
      when state.object.guid == caster_guid and is_integer(entry) and entry > 0 do
    {state, [Effects.summon_pet(caster_guid, entry, spell_id)]}
  end

  def apply(
        %Character{internal: %{active_pet_entry: entry}} = state,
        %CastContext{caster_guid: caster_guid},
        %Spell{id: spell_id},
        %Effect{type: type, misc_value: 0},
        _now
      )
      when type in [:summon_pet, :revive_pet] and is_integer(entry) and entry > 0 do
    {state, [Effects.summon_pet(caster_guid, entry, spell_id)]}
  end

  def apply(%Character{} = state, %CastContext{}, _spell, %Effect{type: :dismiss_pet}, _now) do
    Pet.dismiss(state)
  end

  def apply(state, %CastContext{}, spell, %Effect{type: :summon_game_object, misc_value: entry}, _now)
      when is_integer(entry) and entry > 0 do
    {state, [Effects.summon_game_object(entry, max(spell.duration_ms || 0, 0))]}
  end

  def apply(
        state,
        %CastContext{
          caster_guid: summoner_guid,
          selected_target_guid: target_guid,
          caster_zone: zone_id,
          caster_position: {_world, _x, _y, _z} = position
        },
        _spell,
        %Effect{type: :summon_player},
        _now
      )
      when is_integer(target_guid) do
    {state, [Effects.summon_request(summoner_guid, target_guid, zone_id, position)]}
  end

  def apply(
        state,
        %CastContext{
          caster_guid: owner_guid,
          caster_position: {_world, caster_x, caster_y, caster_z},
          caster_orientation: orientation,
          destination_position: destination
        },
        spell,
        %Effect{type: :summon_demon, misc_value: entry} = effect,
        _now
      )
      when is_integer(entry) and entry > 0 do
    orientation = orientation || 0.0
    {x, y, z} = summon_effect_position(effect, destination, {caster_x, caster_y, caster_z}, orientation)

    summon = %{
      entry: entry,
      owner_guid: owner_guid,
      position: {x, y, z, orientation},
      despawn_delay_ms: summon_duration(spell),
      despawn_type: 1,
      run?: false,
      unique?: false,
      attack_target: nil,
      script_id: 0,
      post_spawn_spells: Warlock.summon_spells(spell)
    }

    {state, [Effects.summon_creature(summon, [], nil)]}
  end

  def apply(
        state,
        %CastContext{
          caster_guid: owner_guid,
          caster_position: {_world, caster_x, caster_y, caster_z},
          caster_orientation: orientation,
          destination_position: destination
        },
        %Spell{id: spell_id} = spell,
        %Effect{type: :summon_possessed, misc_value: entry} = effect,
        _now
      )
      when is_integer(entry) and entry > 0 do
    orientation = orientation || 0.0
    {x, y, z} = summon_effect_position(effect, destination, {caster_x, caster_y, caster_z}, orientation)

    summon = %{
      entry: entry,
      owner_guid: owner_guid,
      position: {x, y, z, orientation},
      despawn_delay_ms: summon_duration(spell),
      despawn_type: 1,
      run?: false,
      unique?: true,
      attack_target: nil,
      script_id: 0,
      post_spawn_spells: [],
      control: :possessed,
      control_spell_id: spell_id
    }

    {state, [Effects.summon_creature(summon, [], nil)]}
  end

  def apply(state, %CastContext{}, spell, %Effect{type: :summon_totem, summon_slot: slot, misc_value: entry}, _now)
      when slot in 1..4 and is_integer(entry) and entry > 0 do
    {state, [Effects.summon_totem(entry, slot, max(spell.duration_ms || 0, 0))]}
  end

  def apply(
        %{object: %{entry: entry}} = state,
        %CastContext{caster_guid: owner_guid},
        _spell,
        %Effect{type: :tame_creature},
        _now
      )
      when is_integer(entry) and entry > 0 do
    {state, [Effects.tame_creature(owner_guid, entry)]}
  end

  def apply(%Character{} = state, %CastContext{}, spell, %Effect{type: :clear_threat}, now) do
    {state, aura_events} = remove_vanish_stalked(state, spell, now)
    {state, mob_guids} = PlayerCombat.vanish(state, now)

    events =
      aura_events ++
        [Effects.drop_nearby_threat()] ++
        Enum.map(mob_guids, &Effects.drop_threat/1) ++
        vanish_attack_stop_events(state) ++ maybe_vanish_stealth_events(state, spell)

    {state, events}
  end

  def apply(state, %CastContext{} = context, _spell, %Effect{type: :attack_me}, _now) do
    {Threat.taunt(state, context.caster_guid), []}
  end

  def apply(
        %{unit: %{target: target}} = state,
        %CastContext{} = context,
        spell,
        %Effect{type: :add_extra_attacks} = effect,
        _now
      )
      when is_integer(target) and target > 0 do
    count = max(Amount.roll(spell, effect, context), 1)
    {BTCombat.extra_attacks(state, target, count), []}
  end

  def apply(state, %CastContext{}, _spell, %Effect{type: :add_extra_attacks}, _now), do: {state, []}

  def apply(state, %CastContext{} = context, spell, %Effect{type: :modify_threat} = effect, _now) do
    {Threat.change(state, context.caster_guid, Amount.roll(spell, effect, context)), []}
  end

  def apply(state, %CastContext{}, spell, %Effect{type: :interrupt_cast}, now) do
    case state do
      %{internal: %{casting: casting} = internal, unit: unit} when not is_nil(casting) ->
        if interruptible_cast?(casting) do
          state = %{
            state
            | internal: %{internal | casting: nil},
              unit: %{unit | channel_spell: 0, channel_object: 0}
          }

          state = lock_interrupted_school(state, casting, spell, now)
          {Core.mark_broadcast_update(state), []}
        else
          {state, []}
        end

      _ ->
        {state, []}
    end
  end

  def apply(state, %CastContext{} = context, spell, %Effect{type: :resurrect_new} = effect, _now) do
    if resurrectable?(state) do
      health = max(Amount.roll(spell, effect, context), 1)
      mana = max(effect.misc_value || 0, 0)
      offer_resurrect(state, context, spell, health, mana)
    else
      {state, []}
    end
  end

  def apply(state, %CastContext{} = context, spell, %Effect{type: :resurrect} = effect, _now) do
    if resurrectable?(state) do
      percent = max(Amount.roll(spell, effect, context), 0) / 100
      health = max(trunc((state.unit.max_health || 1) * percent), 1)
      mana = max(trunc((state.unit.max_power1 || 0) * percent), 0)
      offer_resurrect(state, context, spell, health, mana)
    else
      {state, []}
    end
  end

  def apply(state, _context, _spell, _effect, _now), do: {state, []}

  defp interruptible_cast?(%{spell: %Spell{prevention_type: 1}}), do: true
  defp interruptible_cast?(_casting), do: false

  defp lock_interrupted_school(state, %{spell: %Spell{} = interrupted}, %Spell{} = interrupt, now) do
    duration = max(interrupt.duration_ms || 0, 0)

    if duration > 0 do
      Cooldowns.lock_schools(state, Spell.school_mask(interrupted), now + duration)
    else
      state
    end
  end

  defp lock_interrupted_school(state, _casting, _interrupt, _now), do: state

  defp summon_duration(%Spell{duration_ms: duration_ms}) when is_integer(duration_ms) and duration_ms > 0,
    do: duration_ms

  defp summon_duration(%Spell{}), do: 3_600_000

  defp summon_effect_position(%Effect{implicit_target_a: :minion_position}, _destination, {x, y, z}, orientation) do
    {x + 0.5 * :math.cos(orientation), y + 0.5 * :math.sin(orientation), z}
  end

  defp summon_effect_position(%Effect{}, {x, y, z}, _caster_position, _orientation), do: {x, y, z}
  defp summon_effect_position(%Effect{}, nil, caster_position, _orientation), do: caster_position

  defp maybe_vanish_stealth_events(state, %Spell{} = spell) do
    if Rogue.vanish?(spell), do: vanish_stealth_events(state), else: []
  end

  defp remove_vanish_stalked(state, %Spell{} = spell, now) do
    if Rogue.vanish?(spell) do
      Aura.remove_aura_types(state, [:mod_stalked, :mod_root, :mod_decrease_speed], now)
    else
      {state, []}
    end
  end

  defp vanish_stealth_events(%{object: %{guid: guid}, unit: %{level: level}, internal: %{spellbook: spellbook}})
       when is_map(spellbook) do
    spell_id =
      spellbook
      |> Map.values()
      |> Enum.filter(&Rogue.stealth?/1)
      |> Enum.max_by(&(&1.rank || 0), fn -> nil end)
      |> case do
        %Spell{id: id} -> id
        _ -> nil
      end

    if is_integer(spell_id), do: [Effects.trigger_spell(guid, level || 1, guid, spell_id)], else: []
  end

  defp vanish_stealth_events(_state), do: []

  defp vanish_attack_stop_events(%{object: %{guid: guid}, unit: %{target: target}})
       when is_integer(target) and target > 0 do
    [Effects.attack_stop(guid, target)]
  end

  defp vanish_attack_stop_events(_state), do: []

  defp resurrectable?(%{player: _player} = state) do
    Core.dead?(state) or Death.ghost?(state)
  end

  defp resurrectable?(_state), do: false

  defp offer_resurrect(%{internal: internal} = state, %CastContext{} = context, spell, health, mana) do
    pending = %{
      caster_guid: context.caster_guid,
      position: context.caster_position,
      health: health,
      mana: mana
    }

    state = %{state | internal: %{internal | pending_resurrect: pending}}
    {state, [Effects.resurrect_request(context.caster_guid, spell.id, health, mana)]}
  end
end
