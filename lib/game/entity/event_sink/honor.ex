defmodule ThistleTea.Game.Entity.EventSink.Honor do
  @moduledoc false

  alias ThistleTea.Game.Entity.EffectResolver.Honor, as: HonorResolver
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Honor.Combat
  alias ThistleTea.Game.World.System.Honor, as: HonorSystem

  def emit(entity, %Effects.HonorContribution{} = effect, _context) do
    {entity, history} = Combat.receive_damage(entity, effect)

    if history do
      shares = HonorResolver.shares(entity, history, effect.now)
      HonorSystem.player_kill(entity.object.guid, shares)
    end

    entity
  end
end
