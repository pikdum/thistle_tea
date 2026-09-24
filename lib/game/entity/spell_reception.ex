defmodule ThistleTea.Game.Entity.SpellReception do
  @moduledoc """
  Prepares a recipient's outcome and combat decision before applying effects.
  Owners enter combat from that decision, preserving tap and lethal-hit order.
  Current projections supply detection, dispel resistance, and threat modifiers;
  periodic threat is refreshed for every due tick.
  """

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.EffectResolver.Pvp
  alias ThistleTea.Game.Entity.FeignDeath
  alias ThistleTea.Game.Entity.Logic.Aura.Heartbeat
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.DispelResistance
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.HealingReceived
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Entity.Logic.SpellThreat
  alias ThistleTea.Game.Entity.Logic.StealthDetection
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Math
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.AuraRank
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Combat, as: SpellCombat
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.SpellThreat, as: SpellThreatLoader
  alias ThistleTea.Game.World.Metadata

  defmodule Prepared do
    @moduledoc false
    @enforce_keys [:resolution, :decision, :spell]
    defstruct [:resolution, :decision, :spell]
  end

  def receive(target, caster, %Spell{} = spell, now) do
    apply_prepared(target, prepare(target, caster, spell, now), now)
  end

  def prepare(target, %CastContext{} = context, %Spell{} = spell, now) do
    spell =
      if context.caster_guid != target.object.guid and AuraRank.party_aura?(spell),
        do: SpellLoader.aura_rank(spell, target.unit.level),
        else: spell

    case spell do
      nil -> nil
      spell -> prepare_ranked(target, %{context | spell: spell}, spell, now)
    end
  end

  def prepare(target, caster_guid, %Spell{} = spell, now) when is_integer(caster_guid) do
    prepare(target, %CastContext{caster_guid: caster_guid, caster_level: 1}, spell, now)
  end

  def apply_prepared(target, nil, _now), do: {target, []}

  def apply_prepared(target, %Prepared{resolution: resolution, decision: decision, spell: spell}, now) do
    context = resolution.context

    contacts =
      Pvp.spell_contacts(target, context.caster_guid, target.object.guid, spell, resolution.outcome,
        combat_decision: decision,
        now: now
      )

    contacts =
      if context.caster_guid != target.object.guid and
           (decision.combat? or decision.break_stealth? or decision.break_invisibility?) do
        [
          %Effects.SpellContact{
            target_guid: context.caster_guid,
            other_guid: target.object.guid,
            decision: decision,
            now: now
          }
          | contacts
        ]
      else
        contacts
      end

    {target, events} = SpellEffect.apply_prepared(target, resolution, now)
    {target, contacts ++ events}
  end

  def starts_combat?(%Prepared{decision: %{combat?: combat?}}), do: combat?
  def starts_combat?(_prepared), do: false

  defp prepare_ranked(target, context, spell, now) do
    context = FeignDeath.prepare(target, context, spell, now)
    context = threat_context(target, context, spell)
    context = if Heartbeat.spell?(spell), do: %{context | heartbeat_sample: 1 - :rand.uniform()}, else: context

    context =
      if Enum.any?(spell.effects, &(&1.type == :dispel)) do
        %{context | dispel_resistance: resistance(target)}
      else
        context
      end

    resolution = SpellEffect.prepare(target, context, spell)

    decision =
      if context.caster_guid != target.object.guid and Death.alive?(target) and
           Guid.entity_type(context.caster_guid) in [:player, :mob, :pet],
         do: SpellCombat.decide(spell, context, resolution.outcome, detects_caster?(target, context, spell, now)),
         else: %SpellCombat{}

    %Prepared{resolution: resolution, decision: decision, spell: spell}
  end

  defp detects_caster?(target, context, spell, now) do
    source = caster_detection(context, spell)
    detector = target |> StealthDetection.target_metadata() |> Map.put(:guid, target.object.guid)

    case {World.position(target, now), World.position(context.caster_guid, now) || context.caster_position} do
      {{world, x, y, z}, {world, sx, sy, sz}} ->
        orientation = elem(target.movement_block.position, 3)
        behind? = Math.behind?({x, y, orientation}, {sx, sy})
        distance = Math.distance({x, y, z}, {sx, sy, sz})

        StealthDetection.detectable?(detector, source, distance, now, behind?) and
          detection_line_of_sight?(target, context, source)

      {{_world, _, _, _}, {_other_world, _, _, _}} ->
        false

      _ ->
        StealthDetection.detectable?(detector, source, nil, now)
    end
  end

  defp caster_detection(context, %{speed: speed}) when speed > 0,
    do: Metadata.get(context.caster_guid) || context.caster_detection || %{}

  defp caster_detection(context, _spell), do: context.caster_detection || Metadata.get(context.caster_guid) || %{}

  defp detection_line_of_sight?(target, context, source),
    do:
      not Map.get(source, :stealthed?, false) or StealthDetection.marked_by?(source, target.object.guid) or
        World.line_of_sight?(target, context.caster_guid)

  def aura_contexts(%{unit: %{auras: holders}} = target, now) when is_list(holders) do
    for %Holder{} = holder <- holders,
        periodic_due?(holder, now) or Heartbeat.check_due?(holder, now),
        into: %{} do
      context =
        holder.cast_context ||
          %CastContext{
            caster_guid: holder.caster_guid,
            caster_owner_guid: holder.caster_owner_guid,
            reflected_by_guid: holder.reflected_by_guid,
            caster_level: holder.caster_level,
            spell: holder.spell
          }

      context = threat_context(target, context, holder.spell)

      context =
        if Heartbeat.check_due?(holder, now),
          do: %{context | heartbeat_roll: Math.random_int(0, 10_000)},
          else: context

      context =
        if Holder.has_any_type?(holder, [:periodic_leech, :periodic_health_funnel]) do
          %{context | caster_available?: caster_available?(target, holder.caster_guid, now)}
        else
          context
        end

      {{holder.spell.id, holder.caster_guid, holder.item_source}, context}
    end
  end

  def aura_contexts(_target, _now), do: %{}

  defp periodic_due?(holder, now),
    do: Enum.any?(holder.auras, &(is_integer(&1.next_tick_at) and &1.next_tick_at <= now))

  def heal(target, %Effects.HealEntity{spell: %Spell{} = spell, amount: amount} = effect) do
    if Death.alive?(target) do
      context = threat_context(target, %CastContext{caster_guid: effect.source_guid}, spell)
      healing = HealingReceived.amount(target, amount)
      events = SpellThreat.heal_events(target, context, spell, healing, periodic?: true)
      event = Effects.spell_heal(effect.source_guid, target.object.guid, spell, healing, false, proc_type: nil)
      target |> Core.heal(healing) |> Effects.enqueue([event | events])
    else
      target
    end
  end

  def heal(target, %Effects.HealEntity{amount: amount}), do: HealingReceived.heal(target, amount)
  def heal(target, amount) when is_number(amount), do: HealingReceived.heal(target, amount)

  defp caster_available?(%{object: %{guid: guid}} = target, guid, _now), do: Death.alive?(target)

  defp caster_available?(%{internal: %{world: world}}, guid, now) do
    match?(%{alive?: true}, Metadata.get(guid)) and match?({^world, _, _, _}, World.position(guid, now))
  end

  defp threat_context(target, %CastContext{} = context, spell) do
    context = %{context | spell_threat: SpellThreatLoader.get(spell.id) || context.spell_threat}

    case metadata(target, context.caster_guid) do
      %{spell_threat: %SpellThreat{} = projection} -> SpellThreat.put_context(context, spell, projection)
      _missing -> context
    end
  end

  defp resistance(target) do
    Map.new(target.unit.auras || [], fn %Holder{} = holder ->
      projection = caster_projection(target, holder)
      {{holder.spell.id, holder.caster_guid}, DispelResistance.chance(projection, holder.spell)}
    end)
  end

  defp caster_projection(target, %Holder{caster_guid: caster, caster_owner_guid: owner}) do
    case metadata(target, caster) do
      nil -> []
      caster_metadata when owner in [nil, caster] -> Map.get(caster_metadata, :dispel_resistance, [])
      _caster_metadata -> Map.get(metadata(target, owner) || %{}, :dispel_resistance, [])
    end
  end

  defp metadata(%{object: %{guid: guid}} = target, guid) do
    %{dispel_resistance: DispelResistance.projection(target), spell_threat: SpellThreat.projection(target)}
  end

  defp metadata(_target, guid), do: Metadata.get(guid)
end
