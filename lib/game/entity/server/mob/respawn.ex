defmodule ThistleTea.Game.Entity.Server.Mob.Respawn do
  @moduledoc """
  Post-death respawn lifecycle for a mob: schedules the respawn timer when
  the mob dies, defers while loot rolls are pending, and rebuilds the mob at
  its spawn point (fresh tree, position, metadata) when the timer fires.
  """
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Spawn
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Mob, as: MobBT
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Server.Mob.Corpse
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.Faction, as: FactionLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Visibility

  @default_delay_ms 120_000

  def schedule(%Mob{internal: %Internal{spawn: %Spawn{respawn_ref: ref}}} = state) when is_reference(ref) do
    state
  end

  def schedule(%Mob{internal: %Internal{spawn: %Spawn{} = spawn_state} = internal} = state) do
    ref = Process.send_after(self(), :respawn, delay_ms(spawn_state.respawn_delay_ms))
    %{state | internal: %{internal | spawn: %{spawn_state | respawn_ref: ref}}}
  end

  def schedule(%Mob{} = state), do: state

  def handle(%Mob{} = state) do
    cond do
      not Core.dead?(state) ->
        kick_ai_tick()
        clear_ref(state)

      Corpse.rolls_pending?(state) ->
        put_spawn(state, %{state.internal.spawn | respawn_pending?: true})

      true ->
        respawn(state)
    end
  end

  def maybe_continue(%Mob{internal: %Internal{spawn: %Spawn{respawn_pending?: true}}} = state) do
    if not Corpse.rolls_pending?(state) do
      send(self(), :respawn)
    end

    :ok
  end

  def maybe_continue(%Mob{} = _state), do: :ok

  defp respawn(%Mob{} = state) do
    state =
      state
      |> Corpse.remove()
      |> Mob.respawn()
      |> Mob.apply_addon_auras(Time.now())
      |> BT.init(MobBT.tree())
      |> put_spawn_position()
      |> broadcast_respawn()

    kick_ai_tick()
    state
  end

  defp put_spawn_position(%Mob{} = state) do
    World.update_position(state)
    state = Visibility.join_entity(state)
    update_metadata(state)
    state
  end

  defp broadcast_respawn(%Mob{} = state) do
    Core.update_object(state, :create_object2) |> World.broadcast_packet(state)
    state
  end

  defp update_metadata(%Mob{} = state) do
    Metadata.update(state.object.guid, %{
      bounding_radius: state.unit.bounding_radius,
      combat_reach: state.unit.combat_reach,
      level: state.unit.level,
      unit_flags: state.unit.flags,
      alive?: state.unit.health > 0,
      health_pct: Core.health_pct(state)
    })

    Metadata.update(state.object.guid, Mob.visibility_metadata(state))

    Metadata.update(state.object.guid, FactionLoader.metadata(state.unit.faction_template))
  end

  defp clear_ref(%Mob{internal: %Internal{spawn: %Spawn{} = spawn_state}} = state) do
    put_spawn(state, %{spawn_state | respawn_ref: nil})
  end

  defp clear_ref(%Mob{} = state), do: state

  defp put_spawn(%Mob{internal: %Internal{} = internal} = state, %Spawn{} = spawn_state) do
    %{state | internal: %{internal | spawn: spawn_state}}
  end

  defp delay_ms(delay) when is_integer(delay) and delay >= 0, do: delay
  defp delay_ms(_delay), do: @default_delay_ms

  defp kick_ai_tick do
    Process.send_after(self(), :ai_tick, 0)
  end
end
