defmodule ThistleTea.Game.World.Entity.Player.CompanionVisibilityTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Pet.Companion
  alias ThistleTea.Game.Core.Pet.Companion.EntityRef
  alias ThistleTea.Game.Network.Message.SmsgPetSpells
  alias ThistleTea.Game.World.Entity.Player.CompanionOwner.Attachment
  alias ThistleTea.Game.World.Entity.Player.CompanionVisibility
  alias ThistleTea.Game.World.Entity.Player.State

  describe "finish_attachment/2" do
    test "charmed players receive a command bar without creature control requests" do
      ref = %EntityRef{guid: 2, entry: 0, spell_id: 13_181}

      character =
        %Character{object: %Object{guid: 1}, internal: %Internal{}}
        |> Companion.activate(:charm, ref)

      state = %State{guid: 1, character: character}
      attachment = %Attachment{kind: :charm, entity_ref: ref, pid: self(), spells: []}
      assert CompanionVisibility.finish_attachment(state, attachment) == state
      assert_receive {:"$gen_cast", {:send_packet, %SmsgPetSpells{pet_guid: 2} = packet}}
      assert packet == SmsgPetSpells.for_pet(2, [])
      assert length(packet.action_bars) == 10
      refute_received {:"$gen_call", _, {:pet_controls, _, _}}
    end
  end
end
