defmodule ThistleTea.Game.Core.WhoTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Who
  alias ThistleTea.Game.Core.Who.Entry
  alias ThistleTea.Game.Core.Who.Query

  @stormwind 1_519
  @warsong_gulch 3_277
  @human 1
  @dwarf 3
  @orc 2
  @warrior 1
  @mage 8

  describe "list/3" do
    setup [:roster]

    test "lists only the asker's team", %{asker: asker, roster: roster} do
      assert names(Who.list(%Query{}, asker, roster)) == ["Asker", "Bryn", "Cedric", "Dagny"]
    end

    test "filters by level range, race, and class", %{asker: asker, roster: roster} do
      assert names(Who.list(%Query{level_min: 30, level_max: 60}, asker, roster)) == ["Asker", "Dagny"]
      assert names(Who.list(%Query{race_mask: Bitwise.bsl(1, @dwarf)}, asker, roster)) == ["Bryn", "Dagny"]
      assert names(Who.list(%Query{class_mask: Bitwise.bsl(1, @mage)}, asker, roster)) == ["Cedric"]
    end

    test "matches name and guild filters anywhere, ignoring case", %{asker: asker, roster: roster} do
      assert names(Who.list(%Query{name: "ED"}, asker, roster)) == ["Cedric"]
      assert names(Who.list(%Query{guild: "light"}, asker, roster)) == ["Bryn", "Dagny"]
    end

    test "lists the named zones only", %{asker: asker, roster: roster} do
      assert names(Who.list(%Query{zones: [@stormwind]}, asker, roster)) == ["Asker", "Bryn"]
    end

    test "shows a player when any search term is in their name, guild, or zone", %{asker: asker, roster: roster} do
      assert names(Who.list(%Query{terms: ["storm"]}, asker, roster)) == ["Asker", "Bryn"]
      assert names(Who.list(%Query{terms: ["nobody", "light"]}, asker, roster)) == ["Bryn", "Dagny"]
      assert names(Who.list(%Query{terms: ["", ""]}, asker, roster)) == ["Asker", "Bryn", "Cedric", "Dagny"]
    end

    test "inside a battleground lists the asker's zone from their own copy only", %{roster: roster} do
      asker = %{entry("Asker", 60, @human, @warrior, @warsong_gulch) | world: :copy_one}
      same = %{entry("Same", 60, @human, @warrior, @warsong_gulch) | world: :copy_one}
      other = %{entry("Other", 60, @human, @warrior, @warsong_gulch) | world: :copy_two}
      roster = [asker, same, other | roster]

      assert names(Who.list(%Query{zones: [@warsong_gulch]}, asker, roster)) == ["Asker", "Same"]
      assert "Other" in names(Who.list(%Query{}, asker, roster))
    end

    test "lists at most 49 and counts everyone online past that" do
      roster = Enum.map(1..60, &entry("Player#{&1}", 10, @human, @warrior, @stormwind))
      {listed, online} = Who.list(%Query{}, hd(roster), roster)

      assert length(listed) == 49
      assert online == 60
      assert {[_one], 1} = Who.list(%Query{name: "player7"}, hd(roster), Enum.take(roster, 10))
    end
  end

  defp roster(_context) do
    asker = entry("Asker", 40, @human, @warrior, @stormwind)

    roster = [
      asker,
      %{entry("Bryn", 12, @dwarf, @warrior, @stormwind) | guild: "Light's Hope"},
      entry("Cedric", 20, @human, @mage, 12),
      %{entry("Dagny", 60, @dwarf, @warrior, 1) | guild: "Dawn of Light"},
      entry("Grukk", 40, @orc, @warrior, @stormwind)
    ]

    %{asker: asker, roster: roster}
  end

  defp entry(name, level, race, class, zone) do
    %Entry{
      guid: name,
      name: name,
      level: level,
      race: race,
      class: class,
      team: if(race == @orc, do: :horde, else: :alliance),
      zone: zone,
      zone_name: zone_name(zone),
      world: :open
    }
  end

  defp zone_name(@stormwind), do: "Stormwind City"
  defp zone_name(1), do: "Dun Morogh"
  defp zone_name(12), do: "Elwynn Forest"
  defp zone_name(@warsong_gulch), do: "Warsong Gulch"

  defp names({listed, _online}), do: Enum.map(listed, & &1.name)
end
