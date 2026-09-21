defmodule ThistleTea.Game.Player.Gathering do
  @moduledoc """
  Revalidates object-opening casts against live objects and cached locks.
  The object grants loot access and per-spawn gains; the player commits costs
  and skill progress only after a successful opening.
  """
  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.GameObjectTemplate
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.Lock
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.EventSink.Context
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Gathering, as: GatheringLogic
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Inventory.Batch
  alias ThistleTea.Game.Entity.Logic.Inventory.ChangeSet
  alias ThistleTea.Game.Entity.Logic.ItemUse
  alias ThistleTea.Game.Entity.Logic.OpenLock
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.InventoryUpdate
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.Disenchant
  alias ThistleTea.Game.Player.GameObjects
  alias ThistleTea.Game.Player.Looting
  alias ThistleTea.Game.Player.Quests
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.GameObjectTemplate, as: TemplateLoader
  alias ThistleTea.Game.World.Loader.Lock, as: LockLoader
  alias ThistleTea.Game.World.Pathfinding
  alias ThistleTea.Game.World.System.Instance, as: InstanceSystem
  alias ThistleTea.Game.World.Visibility

  def context(state, spell, targets, cast_item_guid) do
    if OpenLock.spell?(spell) do
      with {:ok, template} <- target(state, Target.object_guid(targets)),
           id when is_integer(id) and id > 0 <- GameObjectTemplate.lock_id(template),
           %Lock{} = lock <- LockLoader.get(id),
           {:ok, entry} <- cast_item_entry(state.character, cast_item_guid) do
        {:ok, lock, entry}
      else
        0 -> {:error, :already_open}
        {:error, _reason} = error -> error
        _ -> {:error, :bad_targets}
      end
    end
  end

  def authorize_use(%{character: %Character{} = character}, guid) do
    template = TemplateLoader.cached(Guid.entry(guid))
    id = GameObjectTemplate.lock_id(template)

    if match?(%GameObjectTemplate{type: type} when type in [0, 1, 3], template) and id > 0 do
      OpenLock.key(LockLoader.get(id), &Inventory.count_entry(character.player, &1, fn guid -> ItemStore.get(guid) end))
    else
      :ok
    end
  end

  def complete(
        %{character: %Character{} = character} = state,
        guid,
        %Spell{} = spell,
        cast_item_guid,
        success_events \\ []
      ) do
    with {:ok, lock, entry} <- context(state, spell, Target.object(guid), cast_item_guid),
         :ok <- validate_tools(character, spell),
         {:ok, opened} <- OpenLock.resolve(character, spell, lock, entry) do
      state = Looting.release(state)

      case costs(state.character, spell, cast_item_guid) do
        {:ok, changes} -> open(state, guid, opened, changes, spell.id, success_events)
        {:error, reason} -> failure(state, spell.id, reason)
      end
    else
      {:error, reason} -> failure(state, spell.id, reason)
      _ -> failure(state, spell.id, :bad_targets)
    end
  end

  def open_key(state, guid, %OpenLock{} = opened) do
    case target(state, guid) do
      {:ok, _template} ->
        state = Looting.release(state)
        {:ok, changes} = Inventory.plan(Batch.new(state.character.player), &ItemStore.get/1)
        open(state, guid, opened, changes, nil, [])

      _ ->
        state
    end
  end

  defp open(state, guid, opened, changes, spell_id, success_events) do
    gain = skill_gain(state.character, opened)

    case Entity.call(guid, {:open_lock, Looting.actor(state, guid), opened, match?({:gained, _}, gain)}) do
      {:ok, content, gained?} ->
        skills = if gained?, do: elem(gain, 1), else: changes.player.skills
        changes = ChangeSet.put_player(changes, %{changes.player | skills: skills})
        state |> InventoryUpdate.apply({:ok, changes}) |> emit(success_events) |> project(guid, content)

      {:error, reason} ->
        failure(state, spell_id, reason)

      _ ->
        failure(state, spell_id, :bad_targets)
    end
  end

  defp emit(state, events) do
    %{state | character: EventSink.emit(state.character, events, Context.new(self()))}
  end

  defp project(state, guid, :activate), do: GameObjects.open_object(state, guid)

  defp project(state, guid, loot) do
    state = Quests.credit_entity_interaction(state, guid)
    InstanceSystem.game_object_used(state.character.internal.world, Guid.entry(guid))
    Network.send_packet(%Message.SmsgLootResponse{guid: guid, loot: loot, loot_type: 2})
    %{state | loot_guid: guid, loot_type: :corpse}
  end

  defp skill_gain(character, %OpenLock{gain?: true, skill_id: id, required: required}) do
    GatheringLogic.skill_up(character.player.skills, id, required, :rand.uniform() * 100)
  end

  defp skill_gain(_character, _opened), do: :unchanged

  defp costs(character, spell, cast_item_guid) do
    batch =
      Enum.reduce(spell.reagents || [], Batch.new(character.player), fn {id, count}, batch ->
        Batch.remove(batch, id, count)
      end)

    with {:ok, batch} <- item_cost(batch, character, spell, cast_item_guid) do
      Inventory.plan(batch, &ItemStore.get/1)
    end
  end

  defp item_cost(batch, _character, _spell, nil), do: {:ok, batch}

  defp item_cost(batch, character, spell, guid) do
    with %Item{} = item <- Disenchant.owned_item(character, guid),
         {:ok, spell_id, index, _commit?} when spell_id == spell.id <- ItemUse.on_use_spell(item) do
      ItemUse.plan(batch, item, index)
    else
      _ -> {:error, :item_gone}
    end
  end

  defp cast_item_entry(_character, nil), do: {:ok, nil}

  defp cast_item_entry(character, guid) do
    case Disenchant.owned_item(character, guid) do
      %Item{object: %{entry: entry}} -> {:ok, entry}
      _ -> {:error, :item_gone}
    end
  end

  defp validate_tools(character, spell) do
    if Enum.all?(spell.tools, &(Inventory.count_entry(character.player, &1, fn guid -> ItemStore.get(guid) end) > 0)),
      do: :ok,
      else: {:error, :item_gone}
  end

  defp target(%{character: %Character{} = character} = state, guid) when is_integer(guid) do
    with false <- Core.dead?(character),
         :game_object <- Guid.entity_type(guid),
         true <- Entity.online?(guid) and Visibility.can_see?(state, guid),
         world = character.internal.world,
         {^world, x, y, z} <- World.position(guid),
         distance when is_number(distance) and distance <= 5.0 <- World.distance_between(character, guid),
         {cx, cy, cz, _o} = character.movement_block.position,
         true <- Pathfinding.line_of_sight?(world, {cx, cy, cz}, {x, y, z}),
         %GameObjectTemplate{} = template <- TemplateLoader.cached(Guid.entry(guid)) do
      {:ok, template}
    else
      distance when is_number(distance) -> {:error, :out_of_range}
      _ -> {:error, :bad_targets}
    end
  end

  defp target(_state, _guid), do: {:error, :bad_targets}

  defp failure(state, nil, _reason), do: state

  defp failure(state, spell_id, reason) do
    emit(state, Effects.spell_cast_failed(spell_id, reason))
  end
end
