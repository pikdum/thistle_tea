defmodule ThistleTea.Game.Core.GameEvent.DarkmoonFaireTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.GameEvent.DarkmoonFaire

  @elwynn 4
  @mulgore 5
  @elwynn_building 23
  @mulgore_building 24

  describe "on/1" do
    test "builds in Elwynn for the three days before October's first Monday" do
      assert DarkmoonFaire.on(~D[2026-10-01]) == []
      assert DarkmoonFaire.on(~D[2026-10-02]) == [@elwynn_building]
      assert DarkmoonFaire.on(~D[2026-10-04]) == [@elwynn_building]
    end

    test "opens for a week from the first Monday" do
      assert DarkmoonFaire.on(~D[2026-10-05]) == [@elwynn]
      assert DarkmoonFaire.on(~D[2026-10-11]) == [@elwynn]
      assert DarkmoonFaire.on(~D[2026-10-12]) == []
    end

    test "sets up in Mulgore in odd-numbered months" do
      assert DarkmoonFaire.on(~D[2026-09-04]) == [@mulgore_building]
      assert DarkmoonFaire.on(~D[2026-09-07]) == [@mulgore]
      assert DarkmoonFaire.on(~D[2026-09-14]) == []
    end

    test "skips the build when the first Monday is the 1st" do
      assert DarkmoonFaire.on(~D[2026-05-31]) == []
      assert DarkmoonFaire.on(~D[2026-06-01]) == [@elwynn]
    end
  end
end
