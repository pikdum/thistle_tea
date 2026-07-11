defmodule ThistleTea.Game.Entity.Server.GameObject.Fishing do
  @moduledoc """
  Fishing bobber and fishing-hole state transitions owned by game-object processes.
  """
  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Fishing, as: FishingState
  alias ThistleTea.Game.Entity.Data.Component.Internal.Loot, as: InternalLoot
  alias ThistleTea.Game.Entity.Data.Component.Internal.Spawn
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Logic.Loot
  alias ThistleTea.Game.Entity.Logic.LootSession
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.Fishing, as: FishingLoader
  alias ThistleTea.Game.World.Loader.GameObjectTemplate, as: GameObjectTemplateLoader
  alias ThistleTea.Game.World.Loader.Loot, as: LootLoader
  alias ThistleTea.Game.World.Visibility

  @fishing_hole_type 25
  @fishing_hole_search_range 22.0
  @default_respawn_ms 300_000

  def bite(%GameObject{game_object: game_object, internal: %Internal{fishing: %FishingState{} = fishing}} = state) do
    fishing = %{fishing | ready?: true}
    %{state | game_object: %{game_object | state: 0}, internal: %{state.internal | fishing: fishing}}
  end

  def use(
        %GameObject{object: %{guid: guid}, internal: %Internal{fishing: %FishingState{} = fishing}} = state,
        owner_guid,
        skill
      ) do
    cond do
      fishing.owner_guid != owner_guid ->
        {{:error, :not_owner}, state}

      fishing.consumed? ->
        {{:error, :consumed}, state}

      not fishing.ready? ->
        {{:error, :not_hooked}, consume(state)}

      true ->
        finish_catch(state, guid, skill)
    end
  end

  def use(state, _owner_guid, _skill), do: {{:error, :not_fishing}, state}

  def hole_loot(%GameObject{internal: %Internal{fishing: %FishingState{loot_id: loot_id} = fishing}} = state) do
    loot = LootLoader.generate_gameobject(loot_id, 0, 0)
    uses_left = max((fishing.uses_left || 1) - 1, 0)
    fishing = %{fishing | uses_left: uses_left}
    state = %{state | internal: %{state.internal | fishing: fishing}}
    {{:ok, loot, uses_left}, state}
  end

  def hole_loot(state), do: {{:error, :not_fishing_hole}, state}

  def catch_success?(skill, base_skill, roll) when is_integer(skill) and is_integer(base_skill) and is_integer(roll) do
    skill >= base_skill and roll <= skill - base_skill + 5
  end

  def deplete(%GameObject{} = state) do
    Visibility.leave_entity(state)
    World.remove_position(state)
    Process.send_after(self(), :fishing_hole_respawn, respawn_ms(state))
    state
  end

  def respawn(%GameObject{object: %{entry: entry}, internal: %Internal{fishing: fishing} = internal} = state) do
    case GameObjectTemplateLoader.get(entry) do
      %{data: data} ->
        min_uses = max(Enum.at(data, 2) || 1, 1)
        max_uses = max(Enum.at(data, 3) || min_uses, min_uses)
        fishing = %{fishing | uses_left: Enum.random(min_uses..max_uses)}
        state = %{state | internal: %{internal | fishing: fishing}}
        World.update_position(state)
        Visibility.join_entity(state)

      _ ->
        state
    end
  end

  defp finish_catch(%GameObject{internal: %Internal{fishing: fishing}} = state, guid, skill) do
    base_skill = FishingLoader.base_skill(fishing.area_id, fishing.zone_id)
    success? = catch_success?(skill, base_skill, :rand.uniform(100))

    case if(success?, do: pool_loot(state)) do
      {:ok, loot, pool_guid, uses_left} ->
        state = put_loot(state, loot)
        result = {:ok, loot, %{bobber_guid: guid, pool_guid: pool_guid, pool_uses_left: uses_left}}
        {result, consume(state)}

      _ when success? ->
        loot = LootLoader.generate_fishing(fishing.area_id, fishing.zone_id)
        state = put_loot(state, loot)
        {{:ok, loot, %{bobber_guid: guid, pool_guid: nil}}, consume(state)}

      _ ->
        {{:error, :escaped}, consume(state)}
    end
  end

  defp pool_loot(%GameObject{internal: %{map: map}, movement_block: %{position: {x, y, z, _o}}}) do
    World.nearby_units_exact(:game_objects, map, {x, y, z}, @fishing_hole_search_range)
    |> Enum.find_value(fn {guid, distance} ->
      with %{type: @fishing_hole_type, data: data} <- GameObjectTemplateLoader.get(Guid.entry(guid)),
           radius when is_integer(radius) and radius > 0 <- Enum.at(data, 0),
           true <- distance <= radius,
           {:ok, %Loot{} = loot, uses_left} <- Entity.call(guid, :fishing_hole_loot) do
        {:ok, loot, guid, uses_left}
      else
        _ -> nil
      end
    end)
  end

  defp put_loot(%GameObject{internal: internal} = state, %Loot{} = loot) do
    internal_loot = %InternalLoot{session: LootSession.new(loot, internal.fishing.owner_guid)}
    %{state | internal: %{internal | loot: internal_loot}}
  end

  defp consume(%GameObject{internal: %Internal{fishing: fishing} = internal} = state) do
    %{state | internal: %{internal | fishing: %{fishing | consumed?: true}}}
  end

  defp respawn_ms(%GameObject{internal: %Internal{spawn: %Spawn{respawn_delay_ms: ms}}})
       when is_integer(ms) and ms > 0 do
    ms
  end

  defp respawn_ms(_state), do: @default_respawn_ms
end
