defmodule ThistleTea.Game.Core.Creature.Posture do
  @moduledoc """
  A creature's resting posture from its `creature_addon` row: how it stands,
  sheathes its weapons, idles, and rides. The spawn snapshot keeps it, and a
  creature that gets home takes it back from there, as vmangos
  `HomeMovementGenerator` reloads the addon. Entering combat stands a
  creature up and stops its idle emote (`Core.Combat.Engagement`).
  """

  alias ThistleTea.Game.Core.Entity
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Spawn
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob

  def restore(%Mob{unit: %Unit{} = unit, internal: %Internal{spawn: %Spawn{unit: %Unit{} = rest}}} = mob) do
    rested = %{
      unit
      | stand_state: rest.stand_state,
        sheath_state: rest.sheath_state,
        npc_emote_state: rest.npc_emote_state,
        mount_display_id: rest.mount_display_id
    }

    if rested == unit, do: mob, else: Entity.mark_broadcast_update(%{mob | unit: rested})
  end

  def restore(mob), do: mob
end
