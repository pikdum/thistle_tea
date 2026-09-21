defmodule ThistleTea.Game.Player.Ammunition do
  @moduledoc """
  Selects carried ammunition and commits each ranged launch's inventory cost
  before projecting its projectile or damage to the world.
  """

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.AI.BT.Ranged
  alias ThistleTea.Game.Entity.Logic.Ammunition, as: Ammo
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.CombatControl
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Disarm
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Proficiency
  alias ThistleTea.Game.Entity.Server.Player.TickScheduler
  alias ThistleTea.Game.Network.InventoryUpdate
  alias ThistleTea.Game.Player.ItemCosts
  alias ThistleTea.Game.Player.Projectile
  alias ThistleTea.Game.Player.Reputation
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.World.ItemStore

  def select(%{character: %Character{} = character} = state, entry) when is_integer(entry) and entry >= 0 do
    case selection(character, entry) do
      :ok -> InventoryUpdate.apply(state, {:ok, %{character.player | ammo_id: entry}})
      {:error, reason, guid} -> InventoryUpdate.apply(state, {:error, reason, guid, 0})
    end
  end

  defp selection(character, entry) do
    cond do
      Core.dead?(character) -> {:error, :you_are_dead, 0}
      entry == 0 -> :ok
      true -> selected_item(character, entry)
    end
  end

  defp selected_item(character, entry) do
    case Enum.find(Inventory.owned_items(character.player, &ItemStore.get/1), &(&1.object.entry == entry)) do
      %Item{} = item ->
        template = Item.template(item)

        with true <- template.inventory_type == 24,
             :ok <- Inventory.can_use(character.unit, Proficiency.from_character(character), template, character.player),
             :ok <- Reputation.validate_item_requirement(character, template) do
          :ok
        else
          false -> {:error, :only_ammo_can_go_here, item.object.guid}
          {:error, reason} -> {:error, reason, item.object.guid}
        end

      nil ->
        {:error, :item_not_found, 0}
    end
  end

  def launch(%{character: %Character{}} = state, %Effects.LaunchRanged{} = request) do
    state = ItemCosts.settle(state)

    if current?(state.character, request) do
      state |> launch_current(request) |> TickScheduler.ensure_scheduled()
    else
      state
    end
  end

  defp current?(%Character{internal: %{casting: casting}}, %Effects.LaunchRanged{kind: :cast, request: casting}),
    do: true

  defp current?(%Character{internal: %{auto_shot: shot}}, %Effects.LaunchRanged{kind: :repeat, request: shot}), do: true
  defp current?(_character, _request), do: false

  defp launch_current(state, %Effects.LaunchRanged{request: %{spell: spell}} = request) do
    with :ok <- available(state.character, spell),
         :ok <- Ammo.validate(state.character, spell, &ItemStore.get/1) do
      character = prepare(state.character, request)

      if failed?(character, spell.id) do
        %{state | character: EventSink.emit_pending(character)}
      else
        commit(state, snapshot_projectile(character, spell), spell, request.kind)
      end
    else
      {:error, reason} -> fail(state, spell.id, reason, request.kind)
    end
  end

  defp available(character, spell) do
    with false <- Core.dead?(character),
         :ok <- validate_pacify(character),
         :ok <- Disarm.validate(character, spell) do
      CombatControl.prevention(character, spell)
    else
      true -> {:error, :caster_dead}
      error -> error
    end
  end

  defp validate_pacify(character) do
    if CombatControl.pacified?(character), do: {:error, :pacified}, else: :ok
  end

  defp prepare(character, %Effects.LaunchRanged{kind: :cast, request: %Cast{} = cast, now: now}) do
    Casting.complete(character, %{cast | ammunition: :paid}, now)
  end

  defp prepare(character, %Effects.LaunchRanged{kind: :repeat, request: shot, now: now}) do
    Ranged.fire(character, shot, now)
  end

  defp failed?(character, spell_id) do
    Enum.any?(character.internal.events, &match?(%Effects.SpellCastFailed{spell_id: ^spell_id}, &1))
  end

  defp snapshot_projectile(character, spell) do
    projectile = Projectile.fields(character, spell)

    events =
      Enum.map(character.internal.events, fn
        %Effects.SpellGo{spell_id: id} = effect when id == spell.id -> %{effect | projectile: projectile}
        effect -> effect
      end)

    %{character | internal: %{character.internal | events: events}}
  end

  defp commit(state, character, spell, kind) do
    case Ammo.plan(character, spell, &ItemStore.get/1) do
      {:ok, changes} ->
        state = InventoryUpdate.apply(%{state | character: character}, {:ok, changes})
        %{state | character: EventSink.emit_pending(state.character)}

      _failure ->
        fail(state, spell.id, :no_ammo, kind)
    end
  end

  defp fail(state, spell_id, reason, kind) do
    character = if kind == :cast, do: Casting.cancel(state.character), else: state.character
    character = character |> Ranged.stop() |> Effects.enqueue(Effects.spell_cast_failed(spell_id, reason))
    %{state | character: EventSink.emit_pending(character)}
  end
end
