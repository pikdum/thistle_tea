defmodule ThistleTea.Game.Core.InstanceScript.MoltenCoreSpawnTest do
  use ExUnit.Case, async: false

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Core.InstanceScript
  alias ThistleTea.Game.Core.InstanceScript.MoltenCore

  @moduletag :vmangos_db

  describe "data64/2" do
    test "the boss target and reset roster refer to Molten Core spawns" do
      boss = Mangos.Repo.get!(Mangos.Creature, InstanceScript.data64("instance_molten_core", 12))
      assert {boss.id, boss.map} == {11_988, 409}
      {:ok, _data, _state, resets} = MoltenCore.creature_event(%{}, %{}, %{creature_entry: 11_988, event: :evade})
      ragers = Enum.map(resets, &Mangos.Repo.get!(Mangos.Creature, &1.creature_db_guid))
      assert length(ragers) == 2

      for rager <- ragers do
        assert {rager.id, rager.map} == {11_672, 409}
        assert :math.sqrt((rager.position_x - boss.position_x) ** 2 + (rager.position_y - boss.position_y) ** 2) < 150
      end
    end
  end
end
