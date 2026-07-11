defmodule ThistleTea.Game.Entity.Logic.StealthDetectionTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Logic.StealthDetection

  describe "detectable?/4" do
    test "scales creature detection by level and stealth skill" do
      detector = %{level: 10}
      target = %{stealthed?: true, stealth_skill: 50}

      assert StealthDetection.detectable?(detector, target, 0.8, 1_000)
      refute StealthDetection.detectable?(detector, target, 2.0, 1_000)
    end

    test "always detects a stealthed target inside collision distance" do
      assert StealthDetection.detectable?(%{level: 1}, %{stealthed?: true, stealth_skill: 300}, 1.49, 1_000)
    end

    test "cannot detect a vanished target before its immunity expires" do
      target = %{stealthed?: true, stealth_skill: 0, undetectable_until: 2_000}

      refute StealthDetection.detectable?(%{level: 60}, target, 0.1, 1_999)
      assert StealthDetection.detectable?(%{level: 60}, target, 0.1, 2_000)
    end
  end
end
