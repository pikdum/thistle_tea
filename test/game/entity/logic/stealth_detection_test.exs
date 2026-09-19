defmodule ThistleTea.Game.Entity.Logic.StealthDetectionTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.StealthDetection

  describe "detection_distance/3" do
    test "distinguishes player and creature observers and targets" do
      player = %{level: 10, player?: true}
      target = %{level: 10, player?: true, stealth_skill: 50}

      assert StealthDetection.detection_distance(player, target, false) == 9.0
      assert StealthDetection.detection_distance(player, %{target | player?: false}, false) == 21.0
      assert_in_delta StealthDetection.detection_distance(%{player | player?: false}, target, false), 5 / 6, 0.001
      assert StealthDetection.detection_distance(player, %{target | level: 11, stealth_skill: 55}, false) == 7.5
    end

    test "applies detection bonuses before the cap and facing penalty after it" do
      player = %{level: 10, player?: true, stealth_detection_bonus: 50}
      target = %{level: 10, player?: true, stealth_skill: 50}

      assert StealthDetection.detection_distance(player, target, false) == 24.0
      assert StealthDetection.detection_distance(player, target, true) == 15.0
      assert StealthDetection.detection_distance(%{player | level: 60}, target, false) == 30.0
      assert StealthDetection.detection_distance(%{player | level: 60}, target, true) == 21.0
    end

    test "doubles skill scaling above a three-level advantage" do
      target = %{level: 10, player?: true, stealth_skill: 50}

      assert StealthDetection.detection_distance(%{level: 13, player?: true}, target, false) == 13.5
      assert StealthDetection.detection_distance(%{level: 14, player?: true}, target, false) == 21.0
    end
  end

  describe "target_metadata/1" do
    test "publishes detection auras for the stealth type and caster-specific marks" do
      character = %Character{
        unit: %Unit{
          level: 10,
          auras: [
            %Holder{auras: [%Aura{type: :mod_stealth_detect, misc_value: 0, amount: 50}]},
            %Holder{stacks: 2, auras: [%Aura{type: :mod_stealth_detect, misc_value: 0, amount: 5}]},
            %Holder{auras: [%Aura{type: :mod_stealth_detect, misc_value: 1, amount: 200}]},
            %Holder{caster_guid: 123, auras: [%Aura{type: :mod_stalked}]},
            %Holder{auras: [%Aura{type: :mod_stun}]}
          ]
        },
        internal: %Internal{}
      }

      assert %{player?: true, stealth_detection_bonus: 60, stunned?: true, stalked_by: [123]} =
               StealthDetection.target_metadata(character)
    end
  end

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

    test "stunned observers cannot detect stealth even at collision distance" do
      detector = %{level: 60, stunned?: true}
      target = %{stealthed?: true, stealth_skill: 0}

      refute StealthDetection.detectable?(detector, target, 0.1, 1_000)
      assert StealthDetection.detectable?(detector, %{target | stealthed?: false}, 0.1, 1_000)
    end

    test "a mark reveals concealment only to its caster" do
      target = %{stealthed?: true, stealth_skill: 300, invisibility: %{0 => 200}, stalked_by: [123]}

      assert StealthDetection.detectable?(%{guid: 123, level: 1}, target, 100.0, 1_000)
      refute StealthDetection.detectable?(%{guid: 124, level: 1}, target, 100.0, 1_000)
    end

    test "invisibility still requires its own detection even at collision distance" do
      target = %{stealthed?: true, stealth_skill: 0, invisibility: %{0 => 200}}

      refute StealthDetection.detectable?(%{level: 60}, target, 0.1, 1_000)
      assert StealthDetection.detectable?(%{level: 60, invisibility_detection: %{0 => 200}}, target, 0.1, 1_000)
      refute StealthDetection.detectable?(%{level: 60}, nil, 0.1, 1_000)
    end

    test "publishes level-scaled skill when the flattened rank amount is stale" do
      character = %Character{
        unit: %Unit{
          level: 30,
          auras: [%Holder{auras: [%Aura{type: :mod_stealth, amount: 5}]}]
        },
        internal: %Internal{}
      }

      assert %{stealthed?: true, stealth_skill: 150} = StealthDetection.target_metadata(character)
    end
  end

  describe "detectable?/5" do
    test "rear detection retains collision range and applies the facing penalty" do
      target = %{stealthed?: true, level: 10, player?: true, stealth_skill: 50}
      detector = %{level: 10, player?: true}

      assert StealthDetection.detectable?(detector, target, 9.0, 1_000, false)
      refute StealthDetection.detectable?(detector, target, 9.01, 1_000, false)
      refute StealthDetection.detectable?(detector, target, 1.5, 1_000, true)
      assert StealthDetection.detectable?(detector, target, 1.49, 1_000, true)
    end
  end
end
