defmodule ThistleTea.Game.Entity.EffectResolver.Spells do
  @moduledoc false

  alias ThistleTea.Game.Entity.EffectResolver.Pvp
  alias ThistleTea.Game.Entity.Logic.Aura.ProcDamage
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.ExtraAttacks
  alias ThistleTea.Game.Entity.Logic.SpellTarget
  alias ThistleTea.Game.Entity.SpellTargetResolver
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Focus
  alias ThistleTea.Game.Spell.Scripts
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpellFocus
  alias ThistleTea.Game.World.SpellMagnets

  @heal_threat_radius 100.0

  def resolve(entity, %Effects.CheckSpellFocus{cast: cast, now: now}) do
    [%Effects.SpellFocusResolved{cast: cast, now: now, focus: SpellFocus.find(entity, cast.spell)}]
  end

  def resolve(entity, %Effects.ProcDamage{target_guid: target_guid, spell: spell, effect_index: index}) do
    target = Metadata.query(target_guid, [:alive?, :level, :attacker_spell_hit_chance, :mechanic_resistance])

    with %{alive?: true} <- target,
         {damage_spell, context} <- ProcDamage.prepare(entity, spell, index, target_guid) do
      hit? = ProcDamage.hit?(entity, spell, target, Guid.entity_type(target_guid) == :player)
      context = %{context | hit_outcome: if(hit?, do: :hit, else: :resist)}
      resolved_delivery(entity, Effects.deliver_spell(target_guid, context, damage_spell))
    else
      _invalid -> []
    end
  end

  def resolve(entity, %Effects.DeliverSpell{delay_ms: nil} = effect) do
    resolved_delivery(entity, effect)
  end

  def resolve(_entity, %Effects.DeliverSpell{} = effect), do: [effect]

  def resolve(entity, %Effects.DeliverSpellOutcome{} = effect) do
    Pvp.spell_contacts(entity, effect.source_guid, effect.target_guid, effect.spell, :miss) ++ [effect]
  end

  def resolve(entity, %Effects.SpellDamage{periodic?: true} = effect) do
    Pvp.contacts(entity, effect.source_guid, effect.target_guid, :attack) ++ [effect]
  end

  def resolve(entity, %Effects.SpellHeal{periodic?: true} = effect) do
    Pvp.contacts(entity, effect.source_guid, effect.target_guid, :assist) ++ [effect]
  end

  def resolve(_entity, %Effects.SpellDamage{} = effect), do: [effect]
  def resolve(_entity, %Effects.SpellHeal{} = effect), do: [effect]

  def resolve(entity, %Effects.DeliverSpellToQuery{spell: %Spell{} = spell} = effect) do
    excluded = MapSet.new(effect.exclude_guids)

    entity
    |> SpellTargetResolver.resolve_query(effect.query)
    |> Enum.reject(&MapSet.member?(excluded, &1))
    |> Enum.flat_map(fn target_guid ->
      context = %CastContext{
        caster_guid: effect.source_guid,
        caster_level: effect.source_level,
        target_guid: target_guid,
        target_hostile?: Spell.requires_hostile_target?(spell),
        spell: spell
      }

      resolved_delivery(entity, Effects.deliver_spell(target_guid, context, spell))
    end)
  end

  def resolve(_entity, %Effects.DeliverSpellToQuery{}), do: []

  def resolve(entity, %Effects.HealThreat{} = effect) do
    entity
    |> World.nearby_mobs(@heal_threat_radius)
    |> Enum.map(fn {guid, _distance} ->
      Effects.deliver_heal_threat(guid, effect.source_guid, effect.target_guid, effect.amount)
    end)
  end

  def resolve(%{object: %{guid: guid}}, %Effects.TriggerSpell{source_guid: source, resolve_targets?: true} = effect)
      when is_integer(source) and source != guid do
    [
      Effects.trigger_spell_request(source, effect.spell_id, effect.target_guid,
        base_points: effect.amount,
        cast_item_guid: effect.cast_item_guid,
        effect_index: effect.slot,
        resolve_targets?: true,
        extra_attack?: effect.extra_attack?,
        triggered_by_spell_id: effect.triggering_spell_id
      )
    ]
  end

  def resolve(entity, %Effects.TriggerSpell{} = effect) do
    with %Spell{} = loaded <- SpellLoader.load(effect.spell_id),
         %Spell{} = spell <- loaded |> scripted_proc_spell(effect) |> apply_trigger_override(effect),
         false <- effect.extra_attack? and ExtraAttacks.spell?(spell) do
      resolve_trigger(entity, effect, spell)
    else
      _missing -> []
    end
  end

  def resolved_delivery(entity, %Effects.DeliverSpell{} = effect) do
    Pvp.spell_contacts(entity, effect.cast_context.caster_guid, effect.target_guid, effect.spell, :hit) ++
      [%{effect | delay_ms: projectile_delay_ms(entity, effect)}]
  end

  defp resolve_trigger(entity, effect, spell) do
    if foreign_player_focus?(entity, effect, spell) do
      [
        Effects.trigger_spell_request(effect.source_guid, effect.spell_id, effect.target_guid,
          base_points: effect.amount,
          cast_item_guid: effect.cast_item_guid,
          effect_index: effect.slot,
          resolve_targets?: true,
          extra_attack?: effect.extra_attack?,
          triggered_by_spell_id: effect.triggering_spell_id
        )
      ]
    else
      validate_trigger_focus(entity, effect, spell)
    end
  end

  defp foreign_player_focus?(entity, effect, spell) do
    Focus.required?(spell) and is_integer(effect.source_guid) and
      effect.source_guid != entity.object.guid and Guid.entity_type(effect.source_guid) == :player
  end

  defp validate_trigger_focus(entity, effect, spell) do
    case Focus.validate(entity, spell, SpellFocus.find(entity, spell)) do
      :ok ->
        if effect.resolve_targets? or SpellTarget.area_targeted?(spell) do
          resolve_area_trigger(entity, effect, spell)
        else
          resolve_single_trigger(entity, effect, spell)
        end

      {:error, reason} ->
        [Effects.spell_cast_failed(spell, reason)]
    end
  end

  defp resolve_single_trigger(entity, effect, spell) do
    case triggered_target(entity, effect, spell) do
      nil ->
        []

      target_guid ->
        target_guid = SpellMagnets.redirect(entity, spell, target_guid)
        effect = %{effect | target_guid: target_guid}
        target = Target.unit(target_guid)

        [
          Effects.spell_go(effect.source_guid || entity.object.guid, effect.spell_id, [target_guid], target)
        ] ++ triggered_delivery(entity, effect, spell)
    end
  end

  defp resolve_area_trigger(entity, effect, spell) do
    targets = SpellTargetResolver.resolve(entity, spell, Target.unit(effect.target_guid))

    [
      Effects.spell_go(
        effect.source_guid || entity.object.guid,
        effect.spell_id,
        targets,
        Target.unit(effect.target_guid)
      )
      | Enum.flat_map(targets, fn target_guid ->
          triggered_delivery(entity, %{effect | target_guid: target_guid}, spell)
        end)
    ]
  end

  defp triggered_delivery(entity, %Effects.TriggerSpell{} = effect, spell) do
    context = trigger_context(entity, effect, spell)
    resolved_delivery(entity, Effects.deliver_spell(effect.target_guid, context, spell))
  end

  defp projectile_delay_ms(%{movement_block: %{position: {x, y, z, _o}}}, %Effects.DeliverSpell{
         spell: %Spell{speed: speed},
         target_guid: target_guid
       })
       when is_number(speed) and speed > 0 and is_integer(target_guid) do
    case World.position(target_guid) do
      {_map, tx, ty, tz} ->
        distance = :math.sqrt(:math.pow(tx - x, 2) + :math.pow(ty - y, 2) + :math.pow(tz - z, 2))
        trunc(distance / speed * 1000)

      _missing ->
        0
    end
  end

  defp projectile_delay_ms(_entity, _effect), do: 0

  defp scripted_proc_spell(%Spell{} = spell, %Effects.TriggerSpell{triggering_spell_id: triggering_spell_id}) do
    case Scripts.proc_trigger_spell_id(spell, triggering_spell_id) do
      spell_id when spell_id == spell.id -> spell
      spell_id when is_integer(spell_id) -> SpellLoader.load(spell_id)
      _missing -> nil
    end
  end

  defp apply_trigger_override(%Spell{} = spell, %Effects.TriggerSpell{} = effect) do
    spell
    |> apply_trigger_effect_override(effect)
    |> apply_trigger_duration_override(effect)
  end

  defp apply_trigger_override(nil, _effect), do: nil

  defp apply_trigger_effect_override(%Spell{effects: effects} = spell, %Effects.TriggerSpell{
         slot: index,
         amount: amount
       })
       when is_integer(index) and is_integer(amount) do
    effects =
      Enum.map(effects, fn
        %Spell.Effect{index: ^index} = effect -> %{effect | base_points: amount, die_sides: 0, base_dice: 0}
        effect -> effect
      end)

    %{spell | effects: effects}
  end

  defp apply_trigger_effect_override(spell, _effect), do: spell

  defp apply_trigger_duration_override(%Spell{} = spell, %Effects.TriggerSpell{duration_ms: duration_ms})
       when is_integer(duration_ms) and duration_ms > 0 do
    %{spell | duration_ms: duration_ms, max_duration_ms: duration_ms}
  end

  defp apply_trigger_duration_override(spell, _effect), do: spell

  defp triggered_target(%{object: %{guid: guid}} = entity, %Effects.TriggerSpell{source_guid: guid} = effect, spell) do
    SpellTarget.redirect_trigger_target(entity, effect.target_guid, spell)
  end

  defp triggered_target(_entity, %Effects.TriggerSpell{} = effect, _spell), do: effect.target_guid

  defp trigger_context(%{object: %{guid: guid}} = entity, %Effects.TriggerSpell{source_guid: guid} = effect, spell) do
    %{
      CastContext.from_caster(entity, spell, effect.target_guid)
      | target_hostile?: Spell.requires_hostile_target?(spell),
        triggered?: true,
        cast_item_guid: effect.cast_item_guid,
        extra_attack?: effect.extra_attack?,
        triggered_by_aura?: is_integer(effect.triggering_spell_id),
        target_role: effect.target_role
    }
  end

  defp trigger_context(_entity, %Effects.TriggerSpell{} = effect, spell) do
    %CastContext{
      caster_guid: effect.source_guid,
      triggered?: true,
      cast_item_guid: effect.cast_item_guid,
      extra_attack?: effect.extra_attack?,
      triggered_by_aura?: is_integer(effect.triggering_spell_id),
      caster_level: effect.source_level || 1,
      target_guid: effect.target_guid,
      target_role: effect.target_role,
      target_hostile?: Spell.requires_hostile_target?(spell),
      spell: spell
    }
  end
end
