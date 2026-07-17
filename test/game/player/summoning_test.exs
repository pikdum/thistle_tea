defmodule ThistleTea.Game.Player.SummoningTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Player.Summoning
  alias ThistleTea.Game.WorldRef

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
