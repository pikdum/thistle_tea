defmodule ThistleTea.Game.Entity.Logic.IntoxicationTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BehaviorRunner
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Player, as: PlayerBT
  alias ThistleTea.Game.Entity.Logic.AI.Tick
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Intoxication
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect

  setup [:character]

  describe "drink/3" do
    test "accumulates alcohol and preserves the sobering deadline", %{character: character} do
      tipsy = Intoxication.drink(character, 5, -20_000)
      assert tipsy.player.drunk_value == 1280
      assert tipsy.internal.next_sober_at == -10_000
      assert tipsy.internal.broadcast_update?
      drunk = Intoxication.drink(tipsy, 45, -19_000)
      assert drunk.player.drunk_value == 12_800
      assert drunk.internal.next_sober_at == -10_000
      assert Intoxication.state(drunk.player.drunk_value) == :drunk
    end

    test "clamps alcohol and allows sobering spells", %{character: character} do
      smashed = Intoxication.drink(character, 1000, 0)
      assert smashed.player.drunk_value == 65_535
      assert Intoxication.state(smashed.player.drunk_value) == :smashed
      sober = Intoxication.drink(smashed, -1000, 1)
      assert sober.player.drunk_value == 0
      assert sober.internal.next_sober_at == nil
      refute Intoxication.needs_tick?(sober)
    end

    test "preserves gender and honor bytes in the client projection", %{character: character} do
      player = %{character.player | gender: 1, city_protector_title: 2, honor_rank: 3}
      character = Intoxication.drink(%{character | player: player}, 1000, 0)
      assert Player.bytes_3(character.player) == <<255, 255, 2, 3>>
      sober = Intoxication.clear(character)
      assert Player.bytes_3(sober.player) == <<1, 0, 2, 3>>
    end

    test "ignores creatures and dead characters", %{character: character} do
      mob = %Mob{}
      assert Intoxication.drink(mob, 50, 0) == mob
      dead = %{character | unit: %{character.unit | health: 0}}
      assert Intoxication.drink(dead, 50, 0) == dead
    end
  end

  describe "tick/2" do
    test "sobers through player maintenance while otherwise idle", %{character: character} do
      refute Tick.needs_tick?(character)
      tipsy = Intoxication.drink(character, 1, 0)
      assert Tick.needs_tick?(tipsy)
      assert Tick.player_delay(tipsy, {:running, 30_000}, 1000) == 9000
      assert Intoxication.tick(tipsy, 9999) == tipsy
      assert {:running, sober} = BehaviorRunner.tick(PlayerBT.tree(), tipsy, Context.new(10_000))
      assert sober.player.drunk_value == 0
      assert sober.internal.next_sober_at == nil
      refute Tick.needs_tick?(sober)
    end

    test "late ticks apply one pulse and never double-apply", %{character: character} do
      tipsy = character |> Intoxication.drink(5, 0) |> Intoxication.tick(30_000)
      assert tipsy.player.drunk_value == 1024
      assert tipsy.internal.next_sober_at == 40_000
      assert Intoxication.tick(tipsy, 30_000) == tipsy
    end

    test "restored drunk state gets a deadline", %{character: character} do
      character = %{character | player: %{character.player | drunk_value: 256}}
      assert Tick.player_delay(character, :running, 1000) == 0
      assert Intoxication.tick(character, 1000).internal.next_sober_at == 11_000
    end
  end

  describe "receive/4" do
    test "routes inebriation through ordinary spell effects", %{character: character} do
      spell = %Spell{id: 11_007, effects: [%Effect{type: :inebriate, base_points: 4, base_dice: 1}]}
      assert {tipsy, []} = SpellEffect.receive(character, %CastContext{caster_guid: 1, caster_level: 1}, spell, 0)
      assert tipsy.player.drunk_value == 1280
    end
  end

  describe "take_damage/4" do
    test "clears alcohol at the shared death transition", %{character: character} do
      dead = character |> Intoxication.drink(100, 0) |> Core.take_damage(1000, 1)
      assert dead.unit.health == 0
      assert dead.player.drunk_value == 0
      assert dead.internal.next_sober_at == nil
    end
  end

  describe "state/1" do
    test "matches client drunkenness thresholds" do
      assert Enum.map([0, 1, 2, 12_799, 12_800, 22_999, 23_000], &Intoxication.state/1) ==
               [:sober, :sober, :tipsy, :tipsy, :drunk, :drunk, :smashed]
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
end
