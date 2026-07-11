defmodule ThistleTea.Game.Player.Fishing do
  @moduledoc """
  Player boundary for fishing casts, bobber placement, catches, and skill gains.
  """
  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Component.Internal.Fishing, as: FishingState
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.AI.BT.Spell, as: SpellBT
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Entity.Logic.Skills
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Loader.GameObjectTemplate, as: GameObjectTemplateLoader
  alias ThistleTea.Game.World.Pathfinding

  @bobber_entry 35_591
  @bite_delays_ms [13_000, 17_000, 23_000, 27_000]
  @catch_window_ms 5_000
  @loot_type_fishing 3

  def fishing_spell?(%Spell{effects: effects}) do
    Enum.any?(effects, &(&1.type == :trans_door and &1.implicit_target_a == :caster_fishing_spot))
  end

  def fishing_spell?(_spell), do: false

  def prepare_cast(%{character: character} = state, %Spell{} = spell) do
    if fishing_spell?(spell) do
      case cast_position(character, &:rand.uniform/0) do
        position when is_tuple(position) -> {:ok, Map.put(state, :fishing_position, position)}
        nil -> {:error, :not_fishable, state}
      end
    else
      {:ok, state}
    end
  end

  def start_cast(%{character: character} = state, %Spell{} = spell) do
    if fishing_spell?(spell) do
      spawn_bobber(state, character, state.fishing_position)
    else
      state
    end
  end

  def catch_fish(%{character: character} = state, bobber_guid) do
    skill = Skills.value(character.player.skills, Skills.fishing_skill())

    case Entity.call(bobber_guid, {:fishing_use, state.guid, skill}) do
      {:ok, loot, _catch} ->
        character = advance_skill(character)
        character = character |> SpellBT.clear_cast() |> EventSink.emit_pending()
        Network.send_packet(%Message.SmsgLootResponse{guid: bobber_guid, loot: loot, loot_type: @loot_type_fishing})
        %{state | character: character, loot_guid: bobber_guid}

      {:error, :not_hooked} ->
        character = character |> SpellBT.clear_cast() |> EventSink.emit_pending()
        Network.send_packet(%Message.SmsgFishNotHooked{})
        %{state | character: character}

      {:error, :escaped} ->
        character = character |> SpellBT.clear_cast() |> EventSink.emit_pending()
        Network.send_packet(%Message.SmsgFishEscaped{})
        %{state | character: character}

      _ ->
        state
    end
  end

  def cancel_bobber(%{unit: %{channel_object: guid}} = character) when is_integer(guid) and guid > 0 do
    case GameObjectTemplateLoader.get(Guid.entry(guid)) do
      %{type: 17} -> World.stop_entity(guid)
      _ -> :ok
    end

    character
  end

  def cancel_bobber(character), do: character

  def cast_position(%{internal: %{map: map}, movement_block: %{position: {x, y, z, o}}} = character, random)
      when is_function(random, 0) do
    distance = 10.0 + random.() * 10.0
    max_angle = 10.0 / (20.0 + bounding_radius(character))
    angle = o + (random.() - 0.5) * max_angle
    target_x = x + distance * :math.cos(angle)
    target_y = y + distance * :math.sin(angle)

    with surface_z when is_number(surface_z) <- Pathfinding.query_liquid_surface(map, {target_x, target_y, z + 1.0}),
         true <- fishable_depth?(Pathfinding.find_heights(map, {target_x, target_y}), surface_z),
         true <- Pathfinding.line_of_sight?(map, {x, y, z}, {target_x, target_y, surface_z}) do
      {target_x, target_y, surface_z, o}
    else
      _ -> nil
    end
  end

  defp fishable_depth?(heights, surface_z) do
    heights
    |> Enum.filter(&(&1 <= surface_z))
    |> Enum.max(fn -> surface_z end)
    |> then(&(surface_z - &1 >= 1.0))
  end

  defp bounding_radius(%{unit: %{bounding_radius: radius}}) when is_number(radius) and radius > 0, do: radius
  defp bounding_radius(_character), do: 0.389

  defp spawn_bobber(state, character, position) do
    state = Map.delete(state, :fishing_position)

    with position when is_tuple(position) <- position,
         {px, py, pz, _o} = position,
         {zone, area} <- Pathfinding.get_zone_and_area(character.internal.map, {px, py, pz}),
         template when not is_nil(template) <- GameObjectTemplateLoader.get(@bobber_entry) do
      bite_delay_ms = Enum.random(@bite_delays_ms)

      bobber =
        GameObject.build_summoned(template, character.internal.map, position,
          summoned_by: state.guid,
          despawn_in_ms: bite_delay_ms + @catch_window_ms,
          fishing: %FishingState{
            owner_guid: state.guid,
            area_id: area,
            zone_id: zone,
            bite_delay_ms: bite_delay_ms
          }
        )

      World.start_entity(bobber)

      duration_ms = bite_delay_ms + @catch_window_ms

      character =
        character
        |> adjust_channel(bobber.object.guid, duration_ms)
        |> Core.mark_broadcast_update()
        |> Event.enqueue([Event.channel_update(character.object.guid, duration_ms), Event.object_update(:values)])

      %{state | character: character}
    else
      _ -> state
    end
  end

  defp adjust_channel(%{internal: internal, unit: unit} = character, bobber_guid, duration_ms) do
    casting = internal.casting

    casting =
      if is_struct(casting, Cast) do
        %{casting | channel_ms: duration_ms, ends_at: casting.started_at + duration_ms}
      else
        casting
      end

    %{character | internal: %{internal | casting: casting}, unit: %{unit | channel_object: bobber_guid}}
  end

  defp advance_skill(character) do
    case Skills.fishing_skill_up(character.player.skills) do
      {:gained, skills} ->
        character = %{character | player: %{character.player | skills: skills}}
        CharacterStore.put(character)
        Network.send_packet(Core.update_object(character, :values))
        character

      :unchanged ->
        character
    end
  end
end
