defmodule ThistleTea.Game.Player.EquipmentEligibility do
  @moduledoc """
  Unequips weapons after their proficiency is lost. A single inventory plan
  moves usable storage entries and detaches overflow weapons for return mail.
  """

  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Inventory.Batch
  alias ThistleTea.Game.Entity.Logic.Mail
  alias ThistleTea.Game.Entity.Logic.Proficiency
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.InventoryUpdate
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.PostOffice

  def reconcile(%{character: character} = state, previous) do
    before = Proficiency.from_character(previous)
    after_reset = Proficiency.from_character(character)

    weapons =
      for slot <- [:mainhand, :offhand, :ranged],
          guid = Map.fetch!(character.player, slot),
          is_integer(guid) and guid > 0,
          %Item{} = item <- [ItemStore.get(guid)],
          Proficiency.can_equip?(before, Item.template(item)) == :ok,
          Proficiency.can_equip?(after_reset, Item.template(item)) != :ok,
          do: item

    relocate(state, weapons)
  end

  defp relocate(state, []), do: state

  defp relocate(state, weapons) do
    {batch, mailed} = Enum.reduce(weapons, {Batch.new(state.character.player), []}, &plan_weapon/2)
    {:ok, changes} = Inventory.plan(batch, &ItemStore.get/1)
    Enum.each(mailed, &return_by_mail(state, &1))
    state = InventoryUpdate.apply(state, {:ok, changes})
    Enum.each(mailed, &Network.send_packet(%Message.SmsgDestroyObject{guid: &1.object.guid}))
    state
  end

  defp plan_weapon(item, {batch, mailed}) do
    stored = Batch.relocate(batch, item.object.guid, :carried)

    case Inventory.plan(stored, &ItemStore.get/1) do
      {:ok, _changes} -> {stored, mailed}
      {:error, _reason} -> {Batch.relocate(batch, item.object.guid, :detached), [item | mailed]}
    end
  end

  defp return_by_mail(state, item) do
    {:ok, _mail} =
      PostOffice.post(%{
        sender: state.guid,
        receiver: state.guid,
        sender_type: :normal,
        subject: "Not equipped item",
        stationery: 61,
        deliver_at: Time.now(),
        item_guid: item.object.guid,
        checked: Mail.checked_copied()
      })
  end
end
