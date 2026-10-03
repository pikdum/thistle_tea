defmodule ThistleTea.Game.Core.Creature.PostureTest do
  use ExUnit.Case, async: true

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Core.Creature.Posture
  alias ThistleTea.Game.Core.Entity.Component.Internal.Spawn
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.World.Loader.Mob.Builder, as: MobBuilder

  describe "MobBuilder.build/2" do
    test "a spawn's addon sets how it rests, rides, and holds its weapons" do
      addon = %Mangos.CreatureAddon{stand_state: 3, emote_state: 69, sheath_state: 0, mount_display_id: 2_410}
      mob = build(addon, 0)

      assert %Unit{stand_state: 3, npc_emote_state: 69, sheath_state: 0, mount_display_id: 2_410} = mob.unit
      assert %Spawn{unit: %Unit{stand_state: 3, npc_emote_state: 69}} = mob.internal.spawn
    end

    test "a spawn rides its template's mount unless its addon names another or none" do
      assert build(%Mangos.CreatureAddon{mount_display_id: -1}, 14_575).unit.mount_display_id == 14_575
      assert build(%Mangos.CreatureAddon{mount_display_id: 0}, 14_575).unit.mount_display_id == nil
      assert build(nil, 14_575).unit.mount_display_id == 14_575
    end

    test "a spawn without an addon stands with its weapons out" do
      assert %Unit{stand_state: nil, npc_emote_state: nil, sheath_state: 1, mount_display_id: nil} = build(nil, 0).unit
    end
  end

  describe "restore/1" do
    test "a creature that gets home takes back its spawn posture" do
      mob = build(%Mangos.CreatureAddon{stand_state: 3, emote_state: 69, sheath_state: 0}, 0)
      roused = %{mob | unit: %{mob.unit | stand_state: 0, npc_emote_state: 0, sheath_state: 1}}

      assert %Mob{unit: %Unit{stand_state: 3, npc_emote_state: 69, sheath_state: 0}} = rested = Posture.restore(roused)
      assert rested.internal.broadcast_update?
      assert Posture.restore(mob) == mob
    end
  end

  defp build(addon, template_mount) do
    MobBuilder.build(
      %Mangos.Creature{
        guid: 1,
        id: 10_184,
        curhealth: 100,
        creature_addon: addon,
        creature_movement: [],
        creature_template: %Mangos.CreatureTemplate{
          entry: 10_184,
          name: "Onyxia",
          mount_display_id: template_mount,
          speed_run: 1.0
        }
      },
      apply_addon_auras?: false
    )
  end
end
