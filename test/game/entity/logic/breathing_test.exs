defmodule ThistleTea.Game.Entity.Logic.BreathingTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.AI.BehaviorRunner
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Player, as: PlayerBT
  alias ThistleTea.Game.Entity.Logic.AI.Tick
  alias ThistleTea.Game.Entity.Logic.Breathing
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell

  describe "update/4" do
    setup [:character]

    test "starts only below the surface and counts elapsed server time", %{character: character} do
      assert Breathing.update(character, 1.5, 0) == character
      assert Breathing.update(character, nil, 0) == character
      underwater = Breathing.update(character, 10.0, 0)

      assert [%Effects.StartMirrorTimer{timer: 1, remaining: 60_000, duration: 60_000, scale: -1}] =
               underwater.internal.events

      underwater = Breathing.update(underwater, 10.0, 20_000)
      assert underwater.internal.breath.remaining == 40_000
      assert length(underwater.internal.events) == 1
      assert underwater.unit.health == 1000
    end

    test "recovers at ten times speed and resumes the remaining reserve on redive", %{character: character} do
      underwater = character |> Breathing.update(10.0, 0) |> Breathing.update(10.0, 30_000)
      surfaced = Breathing.update(underwater, 1.5, 30_000)
      assert %Effects.StartMirrorTimer{remaining: 30_000, scale: 10} = List.last(surfaced.internal.events)
      redive = Breathing.update(surfaced, 10.0, 31_000)
      assert redive.internal.breath.remaining == 40_000
      assert redive.internal.breath.scale == -1
      recovered = redive |> Breathing.update(1.5, 31_000) |> Breathing.update(1.5, 33_000)
      assert recovered.internal.breath == nil
      assert %Effects.StopMirrorTimer{timer: 1} = List.last(recovered.internal.events)
    end

    test "drowns at expiration then every two seconds even without movement", %{character: character} do
      underwater = character |> Breathing.update(10.0, 0) |> Breathing.update(10.0, 60_000, 9)
      assert underwater.unit.health == 791
      assert %Effects.EnvironmentalDamage{type: :drowning, damage: 209} in underwater.internal.events
      assert Breathing.update(underwater, 10.0, 61_999).unit.health == 791
      assert Breathing.update(underwater, 10.0, 62_000).unit.health == 591
      assert Breathing.update(underwater, 1.5, 62_000).unit.health == 791
    end

    test "late ticks apply one pulse rather than a burst of catch-up damage", %{character: character} do
      underwater = character |> Breathing.update(10.0, 0) |> Breathing.update(10.0, 120_000)
      assert underwater.unit.health == 800
      assert underwater.internal.breath.next_damage_at == 122_000
    end

    test "drowning uses the shared death lifecycle and stops the timer", %{character: character} do
      character = %{character | unit: %{character.unit | health: 100}}
      drowned = character |> Breathing.update(10.0, 0) |> Breathing.update(10.0, 60_000)
      assert drowned.unit.health == 0
      assert drowned.internal.breath == nil
      assert %Effects.MovementRootChanged{rooted?: true} in drowned.internal.events
      assert %Effects.StopMirrorTimer{timer: 1} in drowned.internal.events
      assert Breathing.update(drowned, 10.0, 70_000) == drowned
    end

    test "leaving water, death, ghosts and godmode clear the timer", %{character: character} do
      underwater = Breathing.update(character, 10.0, 0)
      assert Breathing.update(underwater, nil, 1000).internal.breath == nil

      for protected <- [
            %{underwater | unit: %{underwater.unit | health: 0}},
            %{underwater | player: %{underwater.player | flags: 0x10}},
            %{underwater | internal: %{underwater.internal | godmode: true}}
          ] do
        assert Breathing.update(protected, 10.0, 60_000).internal.breath == nil
      end
    end

    test "water breathing replenishes breath underwater and removal resumes drowning", %{character: character} do
      protected = with_aura(character, :water_breathing, 0)
      assert Breathing.update(protected, 10.0, 0).internal.breath == nil
      underwater = character |> Breathing.update(10.0, 0) |> Breathing.update(10.0, 59_000)
      protected = underwater |> with_aura(:water_breathing, 0) |> Breathing.update(10.0, 59_000)
      assert protected.internal.breath.scale == 10
      protected = Breathing.update(protected, 10.0, 60_000)
      assert protected.unit.health == 1000
      assert protected.internal.breath.remaining == 11_000
      unprotected = %{protected | unit: %{protected.unit | auras: []}} |> Breathing.update(10.0, 60_000)
      assert unprotected.internal.breath.scale == -1
      assert Breathing.update(unprotected, 10.0, 71_000).unit.health == 800
    end

    test "extended breathing modifies maximum duration and removal clamps the reserve", %{character: character} do
      extended = character |> with_aura(:water_breathing_pct, 300) |> Breathing.update(10.0, 0)
      assert extended.internal.breath.duration == 240_000
      expired = %{extended | unit: %{extended.unit | auras: []}} |> Breathing.update(10.0, 10_000)
      assert expired.internal.breath.duration == 60_000
      assert expired.internal.breath.remaining == 50_000
      assert %Effects.StartMirrorTimer{duration: 60_000} = List.last(expired.internal.events)
    end

    test "extending an active reserve preserves time already spent underwater", %{character: character} do
      extended =
        character
        |> Breathing.update(10.0, 0)
        |> with_aura(:water_breathing_pct, 300)
        |> Breathing.update(10.0, 10_000)

      assert extended.internal.breath.duration == 240_000
      assert extended.internal.breath.remaining == 230_000
    end

    test "physical immunity suppresses drowning damage and its log", %{character: character} do
      for type <- [:school_immunity, :damage_immunity] do
        immune = character |> with_aura(type, 0, 1) |> Breathing.update(10.0, 0) |> Breathing.update(10.0, 60_000)

        assert immune.unit.health == 1000
        refute Enum.any?(immune.internal.events, &match?(%Effects.EnvironmentalDamage{}, &1))
      end
    end
  end

  describe "update/5" do
    setup [:character]

    test "uses the current model height and object scale at the waterline", %{character: character} do
      assert Breathing.update(character, 1.5, 0, 0, 2.0).internal.breath == nil
      assert Breathing.update(character, 1.5, 0, 0, 1.0).internal.breath != nil
      enlarged = %{character | object: %{character.object | scale_x: 2.0}}
      assert Breathing.update(enlarged, 1.5, 0, 0, 1.0).internal.breath == nil
    end
  end

  describe "tick/3" do
    setup [:character]

    test "stationary player upkeep resumes breathing after the protective aura expires", %{character: character} do
      protected = with_aura(character, :water_breathing, 0)
      [holder] = protected.unit.auras
      protected = %{protected | unit: %{protected.unit | auras: [%{holder | expires_at: 1000}]}}
      {:running, protected} = BehaviorRunner.tick(PlayerBT.tree(), protected, Context.new(0, liquid_surface: 10.0))
      assert protected.internal.breath == nil
      {:running, exposed} = BehaviorRunner.tick(PlayerBT.tree(), protected, Context.new(1000, liquid_surface: 10.0))
      assert exposed.unit.auras == []
      assert exposed.internal.breath.remaining == 60_000
      {:running, drowning} = BehaviorRunner.tick(PlayerBT.tree(), exposed, Context.new(61_000, liquid_surface: 10.0))
      assert drowning.unit.health == 800
    end
  end

  describe "needs_tick?/1" do
    setup [:character]

    test "keeps stationary swimming and active breath scheduled", %{character: character} do
      refute Tick.needs_tick?(character)
      swimming = %{character | movement_block: %{character.movement_block | movement_flags: 0x00200000}}
      assert Tick.needs_tick?(swimming)
      underwater = Breathing.update(character, 10.0, 0)
      assert Tick.needs_tick?(underwater)
      assert Tick.player_delay(underwater, {:running, 10_000}, 0) <= 1000
    end
  end

  defp character(_context) do
    [
      character: %Character{
        object: %Object{guid: 1},
        player: %Player{flags: 0},
        unit: %Unit{health: 1000, max_health: 1000, level: 10, auras: []},
        internal: %Internal{},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}, movement_flags: 0}
      }
    ]
  end

  defp with_aura(character, type, amount, misc \\ 0) do
    holder = %Holder{spell: %Spell{id: 1}, caster_guid: 1, auras: [%Aura{type: type, amount: amount, misc_value: misc}]}
    %{character | unit: %{character.unit | auras: [holder]}}
  end
end
