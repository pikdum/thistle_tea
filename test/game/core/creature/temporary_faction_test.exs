defmodule ThistleTea.Game.Core.Creature.TemporaryFactionTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Creature.TemporaryFaction
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Creature
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob

  describe "restoration policy" do
    test "restores on combat stop when requested" do
      mob = mob() |> TemporaryFaction.set(113, 0x02) |> TemporaryFaction.restore(:combat_stop)

      assert mob.unit.faction_template == 35
      assert mob.internal.creature.script_faction_original == nil
    end

    test "clears a respawn-scoped override after respawn" do
      mob = mob() |> TemporaryFaction.set(113, 0x01)
      mob = %{mob | unit: %{mob.unit | faction_template: 35}}
      mob = TemporaryFaction.after_respawn(mob)

      assert mob.unit.faction_template == 35
      assert mob.internal.creature.script_faction_original == nil
    end

    test "reapplies a persistent override after respawn" do
      mob = mob() |> TemporaryFaction.set(113, 0)
      mob = %{mob | unit: %{mob.unit | faction_template: 35}}
      mob = TemporaryFaction.after_respawn(mob)

      assert mob.unit.faction_template == 113
      assert mob.internal.creature.script_faction_original == 35
    end
  end

  defp mob do
    %Mob{
      unit: %Unit{faction_template: 35},
      internal: %Internal{creature: %Creature{}}
    }
  end
end
