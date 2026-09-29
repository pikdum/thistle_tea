defmodule ThistleTea.Game.World.Inbound.Interaction do
  @moduledoc "Handles decoded NPC and game object interaction (gossip, binders, bankers, trainers) client messages."

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.Entity.Player.Bank
  alias ThistleTea.Game.World.Entity.Player.GameObjects
  alias ThistleTea.Game.World.Entity.Player.Gossip
  alias ThistleTea.Game.World.Entity.Player.HomeBind
  alias ThistleTea.Game.World.Entity.Player.TalentReset
  alias ThistleTea.Game.World.Entity.Player.Training

  def messages do
    [
      Message.CmsgBankerActivate,
      Message.CmsgBinderActivate,
      Message.CmsgGameobjUse,
      Message.CmsgGossipHello,
      Message.CmsgGossipSelectOption,
      Message.CmsgTrainerBuySpell,
      Message.CmsgTrainerList,
      Message.MsgTalentWipeConfirmClient
    ]
  end

  def handle(%Message.CmsgBankerActivate{banker_guid: banker_guid}, state), do: Bank.activate(state, banker_guid)

  def handle(%Message.CmsgBinderActivate{guid: guid}, state), do: HomeBind.activate(state, guid)

  def handle(%Message.CmsgGameobjUse{guid: guid}, %{ready: true, character: %Character{}} = state) do
    GameObjects.use_object(state, guid)
  end

  def handle(%Message.CmsgGameobjUse{}, state), do: state

  def handle(%Message.CmsgGossipHello{guid: guid}, state), do: Gossip.hello(state, guid)

  def handle(%Message.CmsgGossipSelectOption{guid: guid, gossip_list_id: gossip_list_id}, state) do
    Gossip.select(state, guid, gossip_list_id)
  end

  def handle(
        %Message.CmsgTrainerBuySpell{trainer_guid: guid, spell_id: id},
        %{ready: true, character: %Character{}} = state
      ) do
    Training.buy(state, guid, id)
  end

  def handle(%Message.CmsgTrainerBuySpell{}, state), do: state

  def handle(%Message.CmsgTrainerList{guid: guid}, %{ready: true, character: %Character{}} = state) do
    Training.send_list(state, guid)
  end

  def handle(%Message.CmsgTrainerList{}, state), do: state

  def handle(%Message.MsgTalentWipeConfirmClient{trainer_guid: guid}, state), do: TalentReset.complete(state, guid)
end
