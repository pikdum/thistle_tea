defmodule ThistleTea.Game.World.Loader.CreatureSpellListVmangosTest do
  use ExUnit.Case, async: true

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Core.AI.CreatureSpell
  alias ThistleTea.Game.Core.AI.CreatureSpellList
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.World.Loader.CreatureSpellList, as: CreatureSpellListLoader
  alias ThistleTea.Game.World.Loader.Script

  @moduletag :vmangos_db

  describe "load/1" do
    test "loads initial and repeat timing with cast flags" do
      assert %{40_520 => default, 40_521 => cat} = CreatureSpellListLoader.load([40_520, 40_521])
      assert %CreatureSpellList{id: 40_520, spells: [%CreatureSpell{spell_id: 9739} = wrath]} = default
      assert CreatureSpell.flag?(wrath, :main_ranged)
      assert wrath.delay_repeat_min_ms == 2_000
      assert [%CreatureSpell{spell_id: 5217, cast_target: :self} = fury] = cat.spells
      assert CreatureSpell.flag?(fury, :triggered)
      assert fury.delay_initial_min_ms == 12_000
      assert fury.delay_initial_max_ms == 16_000
      assert fury.delay_repeat_min_ms == 30_000
      assert fury.delay_repeat_max_ms == 35_000
      assert CreatureSpellListLoader.load([0, 0xFFFFFFFF]) == %{}
    end
  end

  describe "load_by_ids/2" do
    test "resolves druid phases, weighted alternatives, and list removal" do
      scripts = Script.load_by_ids(Mangos.CreatureAiScript, [405_201, 405_203, 1_616_501, 397_702])
      cat = Enum.find(scripts[405_201], &(&1.command == :creature_spells))
      assert cat.creature_spell_lists[40_521].spells |> Enum.map(& &1.spell_id) == [5217]
      assert ScriptStep.spell_ids(cat) == [5217]
      caster = Enum.find(scripts[405_203], &(&1.command == :creature_spells))
      assert ScriptStep.spell_ids(caster) == [9739]
      random = Enum.find(scripts[1_616_501], &(&1.command == :creature_spells))
      assert ScriptStep.creature_spell_list_options(random) == [{161_650, 33}, {161_651, 33}, {161_652, 34}]
      assert Map.keys(random.creature_spell_lists) |> Enum.sort() == [161_650, 161_651, 161_652]
      clear = Enum.find(scripts[397_702], &(&1.command == :creature_spells))
      assert clear.datalong == 0
      assert clear.dataint == 0
      assert clear.creature_spell_lists == %{}
    end
  end
end
