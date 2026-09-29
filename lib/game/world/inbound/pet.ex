defmodule ThistleTea.Game.World.Inbound.Pet do
  @moduledoc "Handles decoded pet control and stable client messages."

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.Entity.Player.Login
  alias ThistleTea.Game.World.Entity.Player.PetActions
  alias ThistleTea.Game.World.Entity.Player.Pets
  alias ThistleTea.Game.World.Entity.Player.PetStable
  alias ThistleTea.Game.World.Entity.Player.PetUntraining

  def messages do
    [
      Message.CmsgBuyStableSlot,
      Message.CmsgPetAbandon,
      Message.CmsgPetAction,
      Message.CmsgPetCancelAura,
      Message.CmsgPetCastSpell,
      Message.CmsgPetRename,
      Message.CmsgPetSetAction,
      Message.CmsgPetSpellAutocast,
      Message.CmsgPetStopAttack,
      Message.CmsgPetUnlearn,
      Message.CmsgRequestPetInfo,
      Message.CmsgStablePet,
      Message.CmsgStableSwapPet,
      Message.CmsgUnstablePet,
      Message.MsgListStabledPetsClient
    ]
  end

  def handle(%Message.CmsgBuyStableSlot{guid: guid}, state), do: PetStable.buy(state, guid)

  def handle(%Message.CmsgPetAbandon{pet_guid: guid}, state), do: Pets.abandon(state, guid)

  def handle(%Message.CmsgPetAction{} = message, state), do: PetActions.handle(message, state)

  def handle(%Message.CmsgPetCancelAura{pet_guid: guid, spell_id: spell}, state),
    do: PetActions.cancel_aura(state, guid, spell)

  def handle(%Message.CmsgPetCastSpell{} = message, state), do: PetActions.cast(state, message)

  def handle(%Message.CmsgPetRename{pet_guid: guid, name: name}, state), do: Pets.rename(state, guid, name)

  def handle(%Message.CmsgPetSetAction{pet_guid: guid, actions: actions}, state) do
    PetActions.controls(state, guid, {:actions, actions})
  end

  def handle(%Message.CmsgPetSpellAutocast{pet_guid: guid, spell_id: id, enabled?: enabled?}, state) do
    PetActions.controls(state, guid, {:autocast, id, enabled?})
  end

  def handle(%Message.CmsgPetStopAttack{pet_guid: guid}, state), do: PetActions.stop_attack(state, guid)

  def handle(%Message.CmsgPetUnlearn{pet_guid: guid}, state), do: PetUntraining.complete(state, guid)

  def handle(%Message.CmsgRequestPetInfo{}, %{ready: true, character: %Character{}} = state) do
    Login.refresh_companion(state)
  end

  def handle(%Message.CmsgRequestPetInfo{}, state), do: state

  def handle(%Message.CmsgStablePet{guid: guid}, state), do: PetStable.transfer(state, guid, :store)

  def handle(%Message.CmsgStableSwapPet{guid: guid, pet_number: pet_number}, state),
    do: PetStable.transfer(state, guid, {:swap, pet_number})

  def handle(%Message.CmsgUnstablePet{guid: guid, pet_number: pet_number}, state),
    do: PetStable.transfer(state, guid, {:retrieve, pet_number})

  def handle(%Message.MsgListStabledPetsClient{guid: guid}, state), do: PetStable.list(state, guid)
end
