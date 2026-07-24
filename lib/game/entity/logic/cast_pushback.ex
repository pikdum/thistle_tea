defmodule ThistleTea.Game.Entity.Logic.CastPushback do
  @moduledoc """
  Cast pushback on damage (vmangos Spell::Delayed / DelayedChannel): direct
  damage taken while a player is casting delays the cast — or shortens the
  remaining channel — by a decreasing amount per successive hit, unless the
  spell's interrupt flags instead cancel it outright or the caster resists
  the pushback via talents/auras. Only player casters are affected; DoT
  ticks never push back.
  """
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Logic.AI.BT.Spell, as: SpellBT
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.Modifiers

  def on_damage(entity, now, opts \\ [])

  def on_damage(%Character{internal: %Internal{casting: %Cast{} = casting}} = entity, now, opts) when is_integer(now) do
    if Keyword.get(opts, :periodic, false) do
      entity
    else
      apply_damage_reaction(entity, casting, now, Keyword.get(opts, :source))
    end
  end

  def on_damage(entity, _now, _opts), do: entity

  defp apply_damage_reaction(entity, %Cast{channel_started?: true, spell: %Spell{} = spell} = casting, now, source) do
    cond do
      Spell.channel_delayed_on_damage?(spell) ->
        if self_damage?(entity, source) do
          entity
        else
          maybe_shorten_channel(entity, casting, now)
        end

      Spell.channel_cancels_on_damage?(spell) ->
        SpellBT.clear_cast(entity)

      true ->
        entity
    end
  end

  defp apply_damage_reaction(entity, %Cast{spell: %Spell{} = spell} = casting, now, _source) do
    cond do
      Spell.cancels_on_damage?(spell) ->
        entity
        |> Event.enqueue(Event.spell_cast_failed(Cast.spell_id(casting), :interrupted))
        |> SpellBT.clear_cast()

      Spell.pushback_on_damage?(spell) ->
        maybe_push_back(entity, casting, now)

      true ->
        entity
    end
  end

  defp apply_damage_reaction(entity, _casting, _now, _source), do: entity

  defp maybe_push_back(%Character{internal: %Internal{} = internal, object: %{guid: guid}} = entity, casting, now) do
    if resist_pushback?(entity, casting.spell) do
      entity
    else
      {casting, delta} = Cast.push_back_cast(casting, now)
      entity = %{entity | internal: %{internal | casting: casting}}

      if delta > 0 do
        Event.enqueue(entity, Event.spell_delayed(guid, delta))
      else
        entity
      end
    end
  end

  defp maybe_shorten_channel(%Character{internal: %Internal{} = internal, object: %{guid: guid}} = entity, casting, now) do
    if resist_pushback?(entity, casting.spell) do
      entity
    else
      {casting, reduction, new_remaining} = Cast.shorten_channel(casting, now)
      entity = %{entity | internal: %{internal | casting: casting}}
      entity = delay_channel_auras(entity, casting, reduction, now)

      cond do
        new_remaining <= 0 -> SpellBT.clear_cast(entity)
        reduction > 0 -> Event.enqueue(entity, Event.channel_update(guid, new_remaining))
        true -> entity
      end
    end
  end

  defp delay_channel_auras(
         %Character{object: %{guid: guid}, unit: %{channel_object: target_guid}} = entity,
         casting,
         reduction,
         now
       )
       when is_integer(reduction) and reduction > 0 do
    spell_id = Cast.spell_id(casting)

    cond do
      target_guid in [0, nil, guid] -> AuraLogic.delay_source_spell(entity, spell_id, guid, reduction, now)
      is_integer(target_guid) -> Event.enqueue(entity, Event.delay_aura(guid, target_guid, spell_id, reduction))
      true -> entity
    end
  end

  defp delay_channel_auras(entity, _casting, _reduction, _now), do: entity

  defp resist_pushback?(%Character{} = entity, %Spell{} = spell) do
    chance =
      entity
      |> Modifiers.value(spell, :not_lose_casting_time, 100)
      |> Kernel.+(AuraLogic.flat_amount(entity, :reduce_pushback))
      |> Kernel.-(100)
      |> round()

    chance > 0 and :rand.uniform(100) <= chance
  end

  defp self_damage?(%Character{object: %{guid: guid}}, source), do: source == guid
end
