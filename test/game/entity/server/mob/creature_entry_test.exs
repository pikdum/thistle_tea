defmodule ThistleTea.Game.Entity.Server.Mob.CreatureEntryTest do
  use ExUnit.Case, async: false

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.AIEvent
  alias ThistleTea.Game.Entity.Data.CreatureArchetype
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Data.ScriptStep
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.CreatureArchetype, as: ArchetypeLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.WorldRef

  setup [:creatures]

  describe "handle_cast/2" do
    test "publishes current identity and client fields while retaining the process", %{mob: mob, template: template} do
      {:ok, pid} = World.start_entity(mob)
      guid = mob.object.guid
      Entity.start_script(guid, [%ScriptStep{command: :update_entry, datalong: template.entry}], 0)
      GenServer.cast(pid, {:send_update_to, self()})
      assert_receive {:"$gen_cast", {:send_packet, %UpdateObject{object: object, unit: unit}}}, 1_000
      assert object.guid == guid
      assert object.entry == template.entry
      assert unit.display_id == template.unit.display_id
      assert unit.level == template.unit.level
      assert Entity.pid(guid) == pid
      assert World.entry(guid) == template.entry
      assert Guid.entry(guid) == mob.object.entry

      assert Metadata.query(guid, [:name, :npc_flags, :display_id]) == %{
               name: "Changed",
               npc_flags: 3,
               display_id: 102
             }
    end

    test "incoming EventAI uses cached definitions and respawn restores metadata", %{mob: mob, template: template} do
      event = %AIEvent{
        event_type: :script_event,
        param1: 99,
        param2: 0,
        actions: [[%ScriptStep{command: :update_entry, datalong: template.entry}]]
      }

      mob = %{mob | internal: %{mob.internal | creature: %{mob.internal.creature | ai_events: [event]}}}
      {:ok, pid} = World.start_entity(mob)
      GenServer.cast(pid, {:script_event, 99, 0, 1})
      GenServer.cast(pid, {:send_update_to, self()})
      assert_receive {:"$gen_cast", {:send_packet, %UpdateObject{object: %{entry: entry}}}}, 1_000
      assert entry == template.entry
      assert World.entry(mob.object.guid) == template.entry
      send(pid, {:script_respawn, true})
      GenServer.cast(pid, {:send_update_to, self()})
      assert_receive {:"$gen_cast", {:send_packet, %UpdateObject{object: object, unit: unit}}}, 1_000
      assert object.entry == mob.object.entry
      assert unit.native_display_id == mob.unit.native_display_id
      assert World.entry(mob.object.guid) == mob.object.entry

      assert Metadata.query(mob.object.guid, [:name, :npc_flags, :display_id]) == %{
               name: "Original",
               npc_flags: 0,
               display_id: 101
             }
    end
  end

  describe "World.entry/1" do
    test "uses the encoded entry when the actor has no current projection" do
      assert World.entry(Guid.from_low_guid(:mob, 99, 12_345_678)) == 99
    end
  end

  defp creatures(_context) do
    mob = build(990_511, "Original", 101, 20, 0)
    target = build(990_512, "Changed", 102, 40, 3)
    template = CreatureArchetype.from_mob(target)
    :ets.insert(ArchetypeLoader, {template.entry, [{1, template}]})

    on_exit(fn ->
      World.stop_entity(mob.object.guid)
      Metadata.delete(mob.object.guid)
      :ets.delete(ArchetypeLoader, template.entry)
    end)

    %{mob: mob, template: template}
  end

  defp build(entry, name, display, level, npc_flags) do
    mob =
      %Mangos.Creature{
        guid: Guid.low_guid(Guid.runtime(:mob, entry)),
        id: entry,
        modelid: display,
        selected_level: level,
        curhealth: 100,
        creature_movement: [],
        creature_template: %Mangos.CreatureTemplate{
          entry: entry,
          name: name,
          min_level: level,
          max_level: level,
          faction_alliance: 35,
          npc_flags: npc_flags,
          extra_flags: 2
        }
      }
      |> Mob.build()

    %{mob | internal: %{mob.internal | world: WorldRef.instance(998, 51)}}
  end
end
