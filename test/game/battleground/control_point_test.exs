defmodule ThistleTea.Game.Battleground.ControlPointTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Battleground.ControlPoint

  describe "assault/4" do
    test "neutral claims wait for capture before granting ownership" do
      assert {:assaulted, point} = ControlPoint.assault(%ControlPoint{}, :alliance, 100, 60_000)
      assert point.capture_at == 60_100
      assert ControlPoint.controlled_by(point) == nil
      assert ControlPoint.state(point) == 1
      assert {:unchanged, ^point} = ControlPoint.assault(point, :alliance, 1000, 60_000)
    end

    test "contested neutral claims can be reversed without instant defense" do
      {:assaulted, point} = ControlPoint.assault(%ControlPoint{}, :alliance, 0, 60_000)
      {:assaulted, reversed} = ControlPoint.assault(point, :horde, 40_000, 60_000)
      assert reversed.capture_at == 100_000
      assert reversed.owner == nil
      assert ControlPoint.state(reversed) == 2
      assert {:unchanged, ^reversed} = ControlPoint.capture(reversed, point.revision, 60_000)
    end

    test "assaulting an occupied node suspends control and defenders restore it immediately" do
      owned = %ControlPoint{owner: :alliance}
      assert {:unchanged, ^owned} = ControlPoint.assault(owned, :alliance, 0, 60_000)
      {:assaulted, contested} = ControlPoint.assault(owned, :horde, 0, 60_000)
      assert ControlPoint.controlled_by(contested) == nil
      {:defended, defended} = ControlPoint.assault(contested, :alliance, 10_000, 60_000)
      assert ControlPoint.controlled_by(defended) == :alliance
      assert defended.capture_at == nil
      assert ControlPoint.state(defended) == 3
      assert {:unchanged, ^defended} = ControlPoint.capture(defended, contested.revision, 60_000)
    end
  end

  describe "capture/3" do
    test "requires the current revision and due time, then transfers control once" do
      {:assaulted, point} = ControlPoint.assault(%ControlPoint{owner: :alliance}, :horde, 10, 60_000)
      assert {:unchanged, ^point} = ControlPoint.capture(point, point.revision, 60_009)
      assert {:captured, captured} = ControlPoint.capture(point, point.revision, 60_010)
      assert ControlPoint.controlled_by(captured) == :horde
      assert ControlPoint.state(captured) == 4
      assert {:unchanged, ^captured} = ControlPoint.capture(captured, point.revision, 120_000)
    end
  end
end
