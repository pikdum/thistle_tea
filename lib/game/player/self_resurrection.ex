defmodule ThistleTea.Game.Player.SelfResurrection do
  @moduledoc """
  Validates the death offer and commits self-resurrection with its reagents,
  owner effects, and visibility updates.
  """

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Inventory.Batch
  alias ThistleTea.Game.Entity.Logic.SelfResurrection, as: SelfResurrectionLogic
  alias ThistleTea.Game.Entity.Server.Player, as: PlayerServer
  alias ThistleTea.Game.Network.InventoryUpdate
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Visibility

  def prepare(%Character{} = character, now, get_spell \\ &SpellLoader.load/1, get_item \\ &ItemStore.get/1) do
    spell_id = SelfResurrectionLogic.candidate_spell_id(character)
    spell = get_spell.(spell_id)

    available? =
      SelfResurrectionLogic.available?(character, spell, now) and
        Enum.all?(spell.reagents, fn {entry, count} ->
          Inventory.count_entry(character.player, entry, get_item) >= count
        end)

    %{character | player: %{character.player | self_res_spell: if(available?, do: spell_id, else: 0)}}
  end

  def use(%{ready: true, character: %Character{} = character} = state) do
    now = Time.now()

    with true <- Core.dead?(character) and not Death.ghost?(character),
         spell when not is_nil(spell) <- SpellLoader.load(character.player.self_res_spell || 0),
         {:ok, character, events} <- SelfResurrectionLogic.resurrect(character, spell, now),
         {:ok, change_set} <- plan_reagents(character, spell) do
      state = InventoryUpdate.apply(%{state | character: character}, {:ok, change_set})
      character = state.character |> EventSink.emit(events) |> EventSink.emit_pending()
      state = PlayerServer.maybe_broadcast_update(%{state | character: character})
      Visibility.notify_visibility_changed(state.character)
      Visibility.resync_player(state)
    else
      _unavailable -> state
    end
  end

  def use(state), do: state

  defp plan_reagents(character, spell) do
    spell.reagents
    |> Enum.reduce(Batch.new(character.player), fn {entry, count}, batch -> Batch.remove(batch, entry, count) end)
    |> Inventory.plan(&ItemStore.get/1)
  end
end
