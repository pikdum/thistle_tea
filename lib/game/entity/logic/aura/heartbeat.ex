defmodule ThistleTea.Game.Entity.Logic.Aura.Heartbeat do
  @moduledoc """
  Early aura resistance using VMangos's player break distribution and
  five-second creature checks. Player quantiles and creature rolls arrive
  from the owning boundary; hit chance is snapshotted on application.

  Refreshes retain the quantile and creature timer. Player break deadlines
  restart with the refreshed duration and its diminishing-return rate.
  """

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura.Change
  alias ThistleTea.Game.Entity.Logic.Aura.Transition
  alias ThistleTea.Game.Entity.Logic.SpellResist
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext

  defstruct [:player_delay_ms, :break_at, :next_check_at, :hit_chance_bp]

  @interval_ms 5_000
  @creature_exclusions [:mod_fear, :mod_root, :mod_pacify_silence, :mod_confuse]

  def spell?(%Spell{id: id} = spell), do: id in [13_181, 13_327] or Spell.attribute?(spell, :heartbeat_resist)

  def prepare(entity, %Holder{negative?: true, applied_at: start, expires_at: finish} = holder, context)
      when is_integer(start) and is_integer(finish) and finish != -1 and finish - start > 10_000 do
    if spell?(holder.spell) do
      heartbeat = %__MODULE__{
        player_delay_ms: player_delay(entity, context.heartbeat_sample),
        hit_chance_bp: creature_hit_chance(entity, holder.spell, context)
      }

      heartbeat =
        if is_integer(heartbeat.hit_chance_bp),
          do: %{heartbeat | next_check_at: start + @interval_ms},
          else: heartbeat

      if heartbeat.player_delay_ms || heartbeat.next_check_at, do: %{holder | heartbeat: heartbeat}, else: holder
    else
      holder
    end
  end

  def prepare(_entity, holder, _context), do: holder

  def schedule(%Holder{heartbeat: %__MODULE__{player_delay_ms: delay} = heartbeat} = holder) when is_number(delay) do
    at = holder.applied_at + ceil(delay * holder.diminishing_rate)
    %{holder | heartbeat: %{heartbeat | break_at: at}}
  end

  def schedule(holder), do: holder

  def delay(%Holder{heartbeat: %__MODULE__{break_at: at} = heartbeat} = holder, delay_ms, now) when is_integer(at),
    do: %{holder | heartbeat: %{heartbeat | break_at: max(at - delay_ms, now)}}

  def delay(holder, _delay_ms, _now), do: holder

  def event_times(%Holder{heartbeat: %__MODULE__{} = heartbeat}) do
    Enum.filter([heartbeat.break_at, heartbeat.next_check_at], &is_integer/1)
  end

  def event_times(_holder), do: []

  def check_due?(%Holder{heartbeat: %__MODULE__{next_check_at: at}} = holder, now) when is_integer(at),
    do: now >= at and Holder.alive?(holder, now)

  def check_due?(_holder, _now), do: false

  def tick(%{unit: %Unit{auras: holders}} = entity, now, contexts) do
    holders = Enum.flat_map(holders, &tick_holder(&1, now, contexts))
    Transition.run(entity, %Change{holders: holders, cause: :removed, now: now})
  end

  defp tick_holder(%Holder{heartbeat: %__MODULE__{} = heartbeat} = holder, now, contexts) do
    cond do
      not Holder.alive?(holder, now) -> [holder]
      is_integer(heartbeat.break_at) and now >= heartbeat.break_at -> []
      check_due?(holder, now) -> check_creature(holder, now, contexts)
      true -> [holder]
    end
  end

  defp tick_holder(holder, _now, _contexts), do: [holder]

  defp check_creature(%Holder{heartbeat: heartbeat} = holder, now, contexts) do
    case Map.get(contexts, {holder.spell.id, holder.caster_guid, holder.item_source}) do
      %CastContext{heartbeat_roll: roll} when is_integer(roll) and roll in 0..10_000 ->
        if roll < 10_000 - heartbeat.hit_chance_bp do
          []
        else
          at = heartbeat.next_check_at
          next = at + (div(now - at, @interval_ms) + 1) * @interval_ms
          [%{holder | heartbeat: %{heartbeat | next_check_at: next}}]
        end

      _missing ->
        [holder]
    end
  end

  defp player_delay(entity, sample) when is_number(sample) and sample > 0 and sample < 1 do
    if player_controlled?(entity), do: max(12_000 + 3_000 / :math.log(99) * :math.log(sample / (1 - sample)), 0)
  end

  defp player_delay(_entity, _sample), do: nil

  defp player_controlled?(%Character{}), do: true

  defp player_controlled?(%{unit: %Unit{charmed_by: charmer}}) when is_integer(charmer) and charmer > 0,
    do: Guid.entity_type(charmer) == :player

  defp player_controlled?(%{internal: %{pet: %{owner_guid: owner}}}), do: Guid.entity_type(owner) == :player
  defp player_controlled?(%{unit: %Unit{summoned_by: owner}}), do: Guid.entity_type(owner) == :player
  defp player_controlled?(_entity), do: false

  defp creature_hit_chance(%Mob{} = entity, spell, %CastContext{caster_guid: caster} = context)
       when is_integer(caster) do
    if Spell.attribute?(spell, :heartbeat_resist) and not Enum.any?(spell.effects, &(&1.aura in @creature_exclusions)) do
      target = Map.put(SpellResist.defense_snapshot(entity), :level, entity.unit.level)

      SpellResist.context_hit_chance_bp(context, spell, target, false)
    end
  end

  defp creature_hit_chance(_entity, _spell, _context), do: nil
end
