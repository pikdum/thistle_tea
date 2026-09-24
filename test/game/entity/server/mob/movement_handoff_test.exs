defmodule ThistleTea.Game.Entity.Server.Mob.MovementHandoffTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura.ControlSync
  alias ThistleTea.Game.Entity.Server.Mob, as: MobServer
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.World.Visibility
  alias ThistleTea.Game.WorldRef

  setup [:released_creature]

  describe "handle_cast/2" do
    test "settles a released creature's last position once", %{mob: mob, caster: caster} do
      movement = %{mob.movement_block | position: {1.0, 0.0, 0.0, 0.0}}
      payload = MovementBlock.movement_info_to_binary(movement)
      assert {:noreply, moved} = MobServer.handle_cast({:finish_movement, caster, payload}, mob)
      assert moved.movement_block.position == movement.position
      assert moved.internal.pet == nil
      assert moved.internal.movement_handoff == nil
      assert World.position(mob.object.guid) == {mob.internal.world, 1.0, 0.0, 0.0}
      assert MobServer.handle_cast({:finish_movement, caster, payload}, moved) == {:noreply, moved}
      Visibility.leave_entity(moved)
    end
  end

  defp released_creature(_context) do
    caster = System.unique_integer([:positive, :monotonic])
    guid = Guid.from_low_guid(:mob, 38, System.unique_integer([:positive, :monotonic]))
    world = WorldRef.instance(451, caster)
    holder = %Holder{caster_guid: caster, spell: %Spell{id: 605}, auras: [%Aura{type: :mod_possess}]}

    mob = %Mob{
      object: %Object{guid: guid},
      unit: %Unit{health: 100, max_health: 100, flags: 0, auras: [holder], faction_template: 14, npc_flags: 0},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}, movement_flags: 0},
      internal: %Internal{world: world}
    }

    {possessed, _} = ControlSync.sync(mob, Time.now())
    {released, _} = ControlSync.sync(put_in(possessed.unit.auras, []), Time.now())

    on_exit(fn ->
      SpatialHash.remove(:mobs, guid)
      Metadata.delete(guid)
    end)

    %{mob: released, caster: caster}
  end
end
