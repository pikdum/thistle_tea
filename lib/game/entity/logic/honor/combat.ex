defmodule ThistleTea.Game.Entity.Logic.Honor.Combat do
  @moduledoc """
  Captures received player damage before death removes auras, then consumes
  the history exactly once when its owner interprets the lethal hit.
  """

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Honor.Damage
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Honor.Contribution

  def on_damage(%Character{} = entity, previous_health, damage, new_health, now, opts)
      when previous_health > 0 and damage > 0 do
    Effects.enqueue(entity, %Effects.HonorDamage{
      source_guid: Keyword.get(opts, :source),
      damage: damage,
      now: now,
      lethal?: new_health == 0,
      honorless?: Aura.has_aura?(entity, :honorless_target)
    })
  end

  def on_damage(%Mob{internal: %{creature: creature, pet: nil, totem: nil}} = entity, health, damage, 0, _now, opts)
      when health > 0 and damage > 0 and (creature.civilian? or creature.racial_leader?) do
    if Aura.has_aura?(entity, :honorless_target) do
      entity
    else
      Effects.enqueue(entity, %Effects.HonorCreatureKill{source_guid: Keyword.get(opts, :source)})
    end
  end

  def on_damage(entity, _previous_health, _damage, _new_health, _now, _opts), do: entity

  def receive_damage(%Character{} = entity, %Effects.HonorContribution{} = effect) do
    history =
      if effect.player_guid == entity.object.guid do
        Contribution.current(entity.internal.honor_damage, effect.now)
      else
        Contribution.record(entity.internal.honor_damage, effect.player_guid, effect.damage, effect.now)
      end

    if effect.lethal? do
      entity = %{entity | internal: %{entity.internal | honor_damage: %Damage{}}}
      {entity, if(!effect.honorless?, do: history)}
    else
      {%{entity | internal: %{entity.internal | honor_damage: history}}, nil}
    end
  end
end
