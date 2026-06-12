defmodule ThistleTea.TelemetryTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Telemetry

  describe "handle_event/4" do
    test "stores mob ai tick samples by wake reason" do
      :ets.match_delete(:telemetry, {:mob_ai_tick, :_, :_, :_})

      Telemetry.handle_event(
        [:thistle_tea, :mob, :ai_tick],
        %{duration: 10, next_delay_ms: 250},
        %{wake_reason: :attack},
        nil
      )

      assert :ets.match_object(:telemetry, {:mob_ai_tick, :_, :_, :_}) == [{:mob_ai_tick, :attack, 10, 250}]
    end
  end
end
