defmodule ThistleTea.Game.Network.Message.CmsgCancelAutoRepeatSpellTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Network.Message.CmsgCancelAutoRepeatSpell

  test "decodes the empty Vanilla payload" do
    assert CmsgCancelAutoRepeatSpell.from_binary(<<>>) == %CmsgCancelAutoRepeatSpell{}
  end

  test "clears an active auto shot" do
    character = %Character{
      unit: %Unit{health: 100, max_health: 100},
      internal: %Internal{auto_shot: %{target_guid: 42}}
    }

    state =
      CmsgCancelAutoRepeatSpell.handle(%CmsgCancelAutoRepeatSpell{}, %{
        character: character,
        player_tick_ref: nil
      })

    assert state.character.internal.auto_shot == nil
  end
end
