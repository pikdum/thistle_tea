defmodule ThistleTea.Game.Network.UpdateBatcher do
  @moduledoc """
  Coalesces queued update-object casts from the connection handler's mailbox
  into one SMSG_UPDATE_OBJECT packet, deduping values blocks so a guid never
  appears twice in a single send (older blocks lose to the newest).

  Every update — including the ones drained out of the mailbox — goes through
  the caller's `personalize` function, so per-recipient field rewrites cannot
  be skipped by coalescing.
  """
  alias ThistleTea.Game.Network.UpdateObject

  @update_batch_max 100

  def batch(%UpdateObject{} = update, recipient_guid, personalize \\ & &1) do
    updates = accumulate(update, personalize)
    {UpdateObject.to_packet(updates, recipient_guid), updates}
  end

  defp accumulate(%UpdateObject{} = update, personalize) do
    [update]
    |> drain_pending(1)
    |> Enum.reverse()
    |> Enum.map(personalize)
    |> dedupe_values()
  end

  defp dedupe_values(updates) do
    {kept, _seen} =
      updates
      |> Enum.reverse()
      |> Enum.reduce({[], MapSet.new()}, fn update, {acc, seen} ->
        case update do
          %UpdateObject{update_type: :values, object: %{guid: guid}} when is_integer(guid) ->
            # credo:disable-for-next-line Credo.Check.Refactor.Nesting
            if MapSet.member?(seen, guid) do
              {acc, seen}
            else
              {[update | acc], MapSet.put(seen, guid)}
            end

          _ ->
            {[update | acc], seen}
        end
      end)

    kept
  end

  defp drain_pending(updates, count) when count < @update_batch_max do
    receive do
      {:"$gen_cast", {:send_packet, %UpdateObject{} = update}} ->
        drain_pending([update | updates], count + 1)
    after
      0 -> updates
    end
  end

  defp drain_pending(updates, _count), do: updates
end
