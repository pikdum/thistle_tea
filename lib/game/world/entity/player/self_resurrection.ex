defmodule ThistleTea.Game.World.Entity.Player.SelfResurrection do
  @moduledoc """
  Validates the death offer and commits self-resurrection with its reagents,
  owner effects, and visibility updates.
  """

  alias ThistleTea.Game.Core.Death
  alias ThistleTea.Game.Core.Death.SelfResurrection, as: SelfResurrectionCore
  alias ThistleTea.Game.Core.Entity
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Inventory
  alias ThistleTea.Game.Core.Inventory.Batch
  alias ThistleTea.Game.Core.Time
  alias ThistleTea.Game.World.Entity.EventSink
  alias ThistleTea.Game.World.Entity.Player, as: PlayerServer
  alias ThistleTea.Game.World.Entity.Player.InventoryUpdate
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Visibility

  def prepare(character, now, get_spell \\ &SpellLoader.load/1, get_item \\ &ItemStore.get/1)

  def prepare(%Character{player: %Player{}} = character, now, get_spell, get_item) do
    spell_id = SelfResurrectionCore.candidate_spell_id(character)
    spell = get_spell.(spell_id)

    available? =
      SelfResurrectionCore.available?(character, spell, now) and
        Enum.all?(spell.reagents, fn {entry, count} ->
          Inventory.count_entry(character.player, entry, get_item) >= count
        end)

    %{character | player: %{character.player | self_res_spell: if(available?, do: spell_id, else: 0)}}
  end

  def prepare(character, _now, _get_spell, _get_item), do: character

  def use(%{ready: true, character: %Character{} = character} = state) do
    now = Time.now()

    with true <- Entity.dead?(character) and not Death.ghost?(character),
         spell when not is_nil(spell) <- SpellLoader.load(character.player.self_res_spell || 0),
         {:ok, character, events} <- SelfResurrectionCore.resurrect(character, spell, now),
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
