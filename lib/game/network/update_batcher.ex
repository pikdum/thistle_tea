defmodule ThistleTea.Game.Network.UpdateBatcher do
  @moduledoc """
  Coalesces queued update-object casts from the connection handler's mailbox
  into one SMSG_UPDATE_OBJECT packet with at most one values-carrying block
  per guid, as vmangos builds them: older values blocks lose to the newest,
  and a create absorbs the newest values for its guid. The client treats a
  values block that trails its own create as a change, so a player's create
  followed by a values block announces every skill as newly gained.

  Every update — including the ones drained out of the mailbox — goes through
  the caller's `personalize` function, so per-recipient field rewrites cannot
  be skipped by coalescing.

  Draining stops at the first other queued send and hands it back to the
  caller to deliver right after the batch, so packets keep the order they were
  sent in. A quest progress packet queued between two updates must reach the
  client before the item create behind it, or the client counts the new item
  twice in its "Item: x/y" popup.
  """
  alias ThistleTea.Game.Network.UpdateObject

  @update_batch_max 100

  def batch(%UpdateObject{} = update, recipient_guid, personalize \\ & &1, visible? \\ fn _ -> true end) do
    {queued, held} = drain_pending([update], 1)
    updates = accumulate(queued, personalize, visible?)
    {UpdateObject.to_packet(updates, recipient_guid), updates, held}
  end

  defp accumulate(queued, personalize, visible?) do
    queued
    |> Enum.reverse()
    |> Enum.filter(visible?)
    |> Enum.map(personalize)
    |> coalesce()
    |> UpdateObject.normalize()
  end

  defp coalesce(updates) do
    {kept, _newest} =
      updates
      |> Enum.reverse()
      |> Enum.reduce({[], %{}}, &coalesce_update/2)

    kept
  end

  defp coalesce_update(%UpdateObject{update_type: :values, object: %{guid: guid}} = update, {kept, newest})
       when is_integer(guid) do
    if Map.has_key?(newest, guid), do: {kept, newest}, else: {[update | kept], Map.put(newest, guid, update)}
  end

  defp coalesce_update(%UpdateObject{update_type: update_type, object: %{guid: guid}} = create, {kept, newest})
       when update_type in [:create_object, :create_object2] and is_integer(guid) do
    case Map.get(newest, guid) do
      %UpdateObject{} = values ->
        {[absorb(create, values) | List.delete(kept, values)], Map.put(newest, guid, :created)}

      _none ->
        {[create | kept], Map.put(newest, guid, :created)}
    end
  end

  defp coalesce_update(update, {kept, newest}), do: {[update | kept], newest}

  defp absorb(%UpdateObject{} = create, %UpdateObject{} = values) do
    %{
      create
      | object: values.object || create.object,
        item: values.item || create.item,
        container: values.container || create.container,
        unit: values.unit || create.unit,
        player: values.player || create.player,
        game_object: values.game_object || create.game_object,
        dynamic_object: values.dynamic_object || create.dynamic_object,
        corpse: values.corpse || create.corpse
    }
  end

  defp drain_pending(updates, count) when count < @update_batch_max do
    receive do
      {:"$gen_cast", {:send_packet, %UpdateObject{} = update}} -> drain_pending([update | updates], count + 1)
      {:"$gen_cast", {:send_packet, message}} -> {updates, [{message, []}]}
      {:"$gen_cast", {:send_packet, message, opts}} -> {updates, [{message, opts}]}
    after
      0 -> {updates, []}
    end
  end

  defp drain_pending(updates, _count), do: {updates, []}
end
