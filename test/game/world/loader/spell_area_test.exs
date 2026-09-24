defmodule ThistleTea.Game.World.Loader.SpellAreaTest do
  use ExUnit.Case, async: true

  alias ThistleTea.DB.Mangos
  alias ThistleTea.DB.Mangos.SpellArea, as: Row
  alias ThistleTea.Game.Spell.Area
  alias ThistleTea.Game.World.Loader.SpellArea

  describe "load/2" do
    setup [:table]

    test "translates rules and replaces previous contents", %{table: table} do
      row = %Row{
        spell: 123,
        area: 139,
        quest_start: 10,
        quest_start_active: 1,
        quest_end: 20,
        aura_spell: -42,
        racemask: 1,
        gender: 1,
        autocast: 1
      }

      assert :ok = SpellArea.load([row], table)

      assert [
               %Area{
                 spell_id: 123,
                 area_id: 139,
                 quest_start: 10,
                 quest_start_active?: true,
                 quest_end: 20,
                 aura_spell: -42,
                 race_mask: 1,
                 gender: 1,
                 autocast?: true
               } = rule
             ] =
               SpellArea.get(123, table)

      assert SpellArea.autocast_rules(table) == [rule]
      assert :ok = SpellArea.load([], table)
      assert SpellArea.get(123, table) == []
      assert SpellArea.autocast_rules(table) == []
    end

    @tag :vmangos_db
    test "loads Moonstalker restrictions and every Lordaeron alternative", %{table: table} do
      rows = Mangos.Repo.all(Row)
      assert length(rows) == 71
      SpellArea.load(rows, table)
      assert [%Area{area_id: 148, autocast?: false}] = SpellArea.get(6298, table)
      rules = SpellArea.get(31_906, table)
      assert Enum.sort(Enum.map(rules, & &1.area_id)) == [139, 2017, 2057, 3456]
      assert Enum.all?(rules, &(&1.aura_spell == 30_238 and &1.autocast?))
      assert SpellArea.autocast_rules(table) == rules
    end
  end

  defp table(_context), do: %{table: :ets.new(__MODULE__, [:public])}
end
