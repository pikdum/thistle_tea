defmodule ThistleTea.Game.World.Entity.Player.SummoningTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Aura.Holder
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Time
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.Entity.Player.Summoning

  describe "request/5" do
    test "Evil Twin silently blocks incoming summons until its aura expires" do
      world = WorldRef.open(1)
      position = {1.0, 2.0, 3.0}
      twin = %Holder{spell: %Spell{id: 23_445}, expires_at: 2_000, auras: []}
      character = %Character{unit: %Unit{health: 100, auras: [twin]}, internal: %Internal{}}
      state = %{character: character}

      assert Summoning.request(state, 7, 440, world, position) == state
      refute_received {:"$gen_cast", {:send_packet, %Message.SmsgSummonRequest{}}}

      {expired, _} = Aura.tick(character, 2_001)
      before = Time.now()
      offered = Summoning.request(%{state | character: expired}, 7, 440, world, position)
      pending = offered.character.internal.pending_summon
      assert pending.summoner_guid == 7
      assert pending.world == world
      assert pending.position == position
      assert pending.expires_at >= before + 120_000
      assert pending.expires_at <= Time.now() + 120_000

      assert_received {:"$gen_cast", {:send_packet, %Message.SmsgSummonRequest{summoner_guid: 7, zone_id: 440}}}
    end
  end

  test "accepts a matching unexpired summon while out of combat" do
    world = %WorldRef{map_id: 1}
    position = {1.0, 2.0, 3.0}

    character = %Character{
      unit: %Unit{health: 100},
      movement_block: %MovementBlock{position: {9.0, 8.0, 7.0, 4.0}},
      internal: %Internal{
        in_combat: false,
        pending_summon: %{summoner_guid: 7, expires_at: 2_000, world: world, position: position}
      }
    }

    assert {%Character{internal: %Internal{pending_summon: nil}}, {^world, {1.0, 2.0, 3.0, 4.0}}} =
             Summoning.accept(character, 7, 1_000)
  end

  test "rejects expired, mismatched, or combat summons" do
    pending = %{summoner_guid: 7, expires_at: 2_000, world: %WorldRef{map_id: 1}, position: {1.0, 2.0, 3.0}}
    character = %Character{unit: %Unit{health: 100}, internal: %Internal{pending_summon: pending}}

    assert {_character, nil} = Summoning.accept(character, 8, 1_000)
    assert {_character, nil} = Summoning.accept(character, 7, 3_000)

    in_combat = %{character | internal: %{character.internal | in_combat: true}}
    assert {_character, nil} = Summoning.accept(in_combat, 7, 1_000)
  end
end
