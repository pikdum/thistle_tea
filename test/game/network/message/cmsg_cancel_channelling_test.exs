defmodule ThistleTea.Game.Network.Message.CmsgCancelChannellingTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Network.Message.CmsgCancelChannelling
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.WorldRef

  test "clears the fishing channel and its bobber" do
    spell = %Spell{id: 7620}

    character = %Character{
      object: %Object{guid: 42},
      unit: %Unit{channel_object: 0xF110_0001, channel_spell: spell.id},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{world: %WorldRef{map_id: 0}, casting: %Cast{spell: spell, channel_ms: 20_000}}
    }

    state = CmsgCancelChannelling.handle(%CmsgCancelChannelling{}, %{guid: 42, character: character})

    assert state.character.internal.casting == nil
    assert state.character.unit.channel_object == 0
    assert state.character.unit.channel_spell == 0
  end
end
