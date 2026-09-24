defmodule ThistleTea.Game.OutdoorPvp.CapturePointTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.OutdoorPvp.CapturePoint
  alias ThistleTea.Game.OutdoorPvp.CapturePoint.Template

  describe "advance/4" do
    setup [:point]

    test "one participant reaches the ownership threshold after four minutes", %{point: point} do
      contested = CapturePoint.advance(point, 1, 0, 239_000)
      assert contested.phase == {:contested, :alliance}
      assert CapturePoint.owner(contested) == nil
      captured = CapturePoint.advance(contested, 1, 0, 1000)
      assert captured.phase == {:progress, :alliance}
      assert CapturePoint.owner(captured) == :alliance
      assert CapturePoint.slider(captured) == 60
    end

    test "opposition subtracts and a tie stops the meter without erasing progress", %{point: point} do
      point = CapturePoint.advance(point, 3, 1, 1000)
      assert point.progress == 2000
      tied = CapturePoint.advance(point, 2, 2, 10_000)
      assert tied.progress == point.progress
      assert tied.phase == :neutral
      assert CapturePoint.slider_changed?(point, tied)
      assert CapturePoint.advance(tied, 0, 0, 30_000) == tied
    end

    test "ownership survives pressure until the neutral band is reached", %{point: point} do
      owned = CapturePoint.advance(point, 1, 0, 1_200_000)
      assert owned.phase == {:controlled, :alliance}
      pressured = CapturePoint.advance(owned, 0, 1, 959_000)
      assert CapturePoint.owner(pressured) == :alliance
      assert pressured.phase == {:progress, :alliance}
      neutral = CapturePoint.advance(pressured, 0, 1, 2000)
      assert CapturePoint.owner(neutral) == nil
      assert neutral.phase == {:contested, :horde}
      horde = CapturePoint.advance(neutral, 0, 1, 479_000)
      assert CapturePoint.owner(horde) == :horde
      assert CapturePoint.slider(horde) == 40
    end

    test "clamps both endpoints and behaves symmetrically", %{point: point} do
      alliance = CapturePoint.advance(point, 5, 0, 1_000_000)
      horde = CapturePoint.advance(point, 0, 5, 1_000_000)
      assert alliance.progress == -horde.progress
      assert alliance.phase == {:controlled, :alliance}
      assert horde.phase == {:controlled, :horde}
      assert CapturePoint.slider(alliance) == 100
      assert CapturePoint.slider(horde) == 0
      assert CapturePoint.advance(alliance, 5, 0, 1000) == alliance
    end

    test "retains fractional progress independently of tick size", %{point: point} do
      split = Enum.reduce(1..1000, point, fn _, point -> CapturePoint.advance(point, 3, 1, 7) end)
      assert split == CapturePoint.advance(point, 3, 1, 7000)
      assert CapturePoint.advance(point, 3, 1, 0) == point
    end

    test "applies the reference speed ceiling for very large population differences", %{point: point} do
      capped = CapturePoint.advance(point, 10_000, 0, 1)
      assert capped.progress == 2500
    end
  end

  describe "enter_states/1" do
    setup [:point]

    test "sends the slider position last and hides it on departure", %{point: point} do
      assert CapturePoint.enter_states(point) == [{2426, 1}, {2428, 20}, {2427, 50}]
      assert CapturePoint.leave_states(point) == [{2426, 0}]
      assert CapturePoint.position_state(point) == {2427, 50}
    end
  end

  defp point(_context) do
    template = %Template{
      entry: 181_899,
      radius: 80,
      display_state: 2426,
      position_state: 2427,
      neutral_state: 2428,
      neutral_percent: 20,
      min_time: 480,
      max_time: 1200
    }

    %{point: CapturePoint.new(template)}
  end
end
