defmodule ThistleTea.Game.Core.Environment.FatigueTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.BehaviorRunner
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.BT.Player, as: PlayerBT
  alias ThistleTea.Game.Core.AI.Tick
  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Aura.Holder
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Environment.Fatigue
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Terrain.Liquid
  alias ThistleTea.Game.Core.Travel.Taxi.Flight
  alias ThistleTea.Game.World.Entity.EventSink
  alias ThistleTea.Game.World.Entity.EventSink.Context, as: SinkContext

  @ocean %Liquid{flags: 0x12, surface: 0.0, floor: -100.0}
  @shore %Liquid{flags: 0x02, surface: 0.0, floor: -10.0}

  setup [:character]

  describe "update/4" do
    test "starts a fatigue bar only in high sea and preserves partial recovery", %{character: character} do
      assert Fatigue.update(character, @shore, 0) == character
      assert Fatigue.update(character, nil, 0) == character
      tired = character |> Fatigue.update(@ocean, 0) |> Fatigue.update(@ocean, 30_000)

      assert [%Effects.StartMirrorTimer{timer: 0, duration: 60_000, remaining: 60_000, scale: -1}] =
               tired.internal.events

      assert tired.internal.fatigue.remaining == 30_000
      shore = Fatigue.update(tired, @shore, 30_000)
      assert %Effects.StartMirrorTimer{timer: 0, remaining: 30_000, scale: 10} = List.last(shore.internal.events)
      returned = Fatigue.update(shore, @ocean, 31_000)
      assert returned.internal.fatigue.remaining == 40_000
      recovered = returned |> Fatigue.update(@shore, 31_000) |> Fatigue.update(@shore, 33_000)
      assert recovered.internal.fatigue == nil
      assert %Effects.StopMirrorTimer{timer: 0} = List.last(recovered.internal.events)
    end

    test "exhausts every two seconds with no catch-up burst and no shore damage", %{character: character} do
      tired = character |> Fatigue.update(@ocean, 0) |> Fatigue.update(@ocean, 60_000, 9)
      assert tired.unit.health == 791
      assert %Effects.EnvironmentalDamage{type: :exhaustion, damage: 209} in tired.internal.events
      assert Fatigue.update(tired, @ocean, 61_999).unit.health == 791
      assert Fatigue.update(tired, @ocean, 62_000).unit.health == 591
      assert Fatigue.update(tired, @shore, 62_000).unit.health == 791
      assert Fatigue.update(tired, @ocean, 120_000).unit.health == 591
    end

    test "uses the death lifecycle and clears fatigue at death or on dry land", %{character: character} do
      tired = %{character | unit: %{character.unit | health: 100}} |> Fatigue.update(@ocean, 0)
      assert Fatigue.update(tired, nil, 60_000).unit.health == 100
      dead = Fatigue.update(tired, @ocean, 60_000)
      assert dead.unit.health == 0
      assert dead.internal.fatigue == nil
      assert %Effects.MovementRootChanged{rooted?: true} in dead.internal.events
      assert %Effects.StopMirrorTimer{timer: 0} in dead.internal.events
      assert Fatigue.update(dead, @ocean, 70_000) == dead
    end

    test "water breathing does not protect against fatigue", %{character: character} do
      protected = with_aura(character, :water_breathing)
      assert protected |> Fatigue.update(@ocean, 0) |> Fatigue.update(@ocean, 60_000) |> then(& &1.unit.health) == 800
    end

    test "taxi, transport, god mode and Spirit of Redemption stop the timer", %{character: character} do
      tired = Fatigue.update(character, @ocean, 0)

      for protected <- [
            %{tired | internal: %{tired.internal | taxi_flight: flight()}},
            %{tired | internal: %{tired.internal | godmode: true}},
            %{
              tired
              | movement_block: %{tired.movement_block | transport_guid: 7, transport_position: {0.0, 0.0, 0.0, 0.0}}
            },
            %{tired | unit: %{tired.unit | shapeshift_form: 32}}
          ] do
        assert Fatigue.update(protected, @ocean, 60_000).internal.fatigue == nil
        assert Fatigue.update(protected, @ocean, 60_000).unit.health == 1000
      end
    end

    test "ghost expiration requests owner-local graveyard rescue without health loss", %{character: character} do
      ghost = %{character | player: %{character.player | flags: 0x10}, unit: %{character.unit | health: 1}}
      rescued = ghost |> Fatigue.update(@ocean, 0) |> Fatigue.update(@ocean, 60_000)
      assert rescued.unit.health == 1
      assert rescued.internal.fatigue == nil
      assert %Effects.RepopAtGraveyard{} in rescued.internal.events
      refute Enum.any?(rescued.internal.events, &match?(%Effects.EnvironmentalDamage{}, &1))

      context = SinkContext.new(self())
      EventSink.emit(rescued, [%Effects.RepopAtGraveyard{}], context)
      assert_receive {:"$gen_cast", :repop_at_graveyard}
    end
  end

  describe "tick/3" do
    test "keeps stationary fatigue scheduled and consumes the supplied terrain snapshot", %{character: character} do
      {:running, tired} = BehaviorRunner.tick(PlayerBT.tree(), character, Context.new(0, terrain_liquid: @ocean))
      assert Tick.needs_tick?(tired)
      assert Tick.player_delay(tired, {:running, 10_000}, 0) <= 1000
      {:running, exhausted} = BehaviorRunner.tick(PlayerBT.tree(), tired, Context.new(60_000, terrain_liquid: @ocean))
      assert exhausted.unit.health == 800
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

  defp with_aura(character, type) do
    holder = %Holder{spell: %Spell{id: 1}, caster_guid: 1, auras: [%Aura{type: type, amount: 0}]}
    %{character | unit: %{character.unit | auras: [holder]}}
  end

  defp flight do
    %Flight{
      token: make_ref(),
      path_ids: [1],
      source_node_id: 1,
      destination_node_id: 2,
      destination_position: {0.0, 0.0, 0.0},
      mount_display_id: 1,
      started_at: 0,
      duration_ms: 120_000
    }
  end
end
