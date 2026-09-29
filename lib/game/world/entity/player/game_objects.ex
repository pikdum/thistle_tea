defmodule ThistleTea.Game.World.Entity.Player.GameObjects do
  @moduledoc """
  Player-side game object interaction: routing CMSG_GAMEOBJ_USE and the
  open-lock spell completion to the chest loot window, and everything else
  to the object's own use handler.
  """
  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Core.Combat.Hostility
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.GameObjectTemplate
  alias ThistleTea.Game.Core.GameObject.GameObjectInteraction
  alias ThistleTea.Game.Core.GameObject.Goober
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Time
  alias ThistleTea.Game.Network.Message.SmsgGameobjectPagetext
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Entity.EventSink
  alias ThistleTea.Game.World.Entity.Player, as: PlayerServer
  alias ThistleTea.Game.World.Entity.Player.Fishing
  alias ThistleTea.Game.World.Entity.Player.Gathering
  alias ThistleTea.Game.World.Entity.Player.Gossip
  alias ThistleTea.Game.World.Entity.Player.Looting
  alias ThistleTea.Game.World.Entity.Player.ObjectTarget
  alias ThistleTea.Game.World.Entity.Player.Quests
  alias ThistleTea.Game.World.Loader.GameObjectTemplate, as: GameObjectTemplateLoader
  alias ThistleTea.Game.World.Loader.Quest, as: QuestLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Outbound
  alias ThistleTea.Game.World.Pathfinding
  alias ThistleTea.Game.World.System.Battleground, as: BattlegroundSystem
  alias ThistleTea.Game.World.System.Instance, as: InstanceSystem

  require Logger

  @go_type_chest 3
  @go_type_chair 7
  @go_type_questgiver 2

  def use_object(%{character: %Character{}} = state, guid) do
    if interactable?(state.character, guid) do
      case Gathering.authorize_use(state, guid) do
        :ok -> open_object(state, guid)
        {:ok, opened} -> Gathering.open_key(state, guid, opened)
        _ -> state
      end
    else
      state
    end
  end

  def interactable?(character, guid) do
    metadata = Metadata.get(guid) || %{}
    enabled? = ((Map.get(metadata, :go_flags) || 0) &&& 0x10) == 0

    enabled? and interactable_template?(character, guid, GameObjectTemplateLoader.cached(Guid.entry(guid)), metadata)
  end

  defp interactable_template?(character, guid, %GameObjectTemplate{type: type} = template, metadata)
       when type in [24, 26],
       do:
         GameObjectInteraction.battleground_allowed?(character) and
           object_in_range?(character, guid, template, metadata)

  defp interactable_template?(character, guid, %GameObjectTemplate{type: 22} = template, metadata),
    do: object_in_range?(character, guid, template, metadata) and not Hostility.hostile?(guid, character)

  defp interactable_template?(character, guid, %GameObjectTemplate{type: type} = template, metadata)
       when type in [0, 1, 9, 10, 23], do: object_in_range?(character, guid, template, metadata)

  defp interactable_template?(_character, _guid, _template, _metadata), do: true

  defp object_in_range?(character, guid, template, metadata) do
    world = character.internal.world
    {x, y, z, _} = character.movement_block.position

    with true <- character.unit.health > 0,
         %{go_spawned?: true, go_rotation: rotation, go_scale: scale} <- metadata,
         {^world, ox, oy, oz} <- World.position(guid),
         true <- GameObjectInteraction.within?({x, y, z}, {ox, oy, oz}, rotation, scale, template.bounds, 5.55556) do
      template.display_id != 295 or Pathfinding.line_of_sight?(world, {x, y, z}, {ox, oy, oz})
    else
      _ -> false
    end
  end

  def open_object(%{character: %Character{}} = state, guid) do
    case GameObjectTemplateLoader.cached(Guid.entry(guid)) do
      %GameObjectTemplate{type: type} = template when type in [9, 10] ->
        case battleground_use(state, guid) do
          :handled -> state
          :unhandled -> use_readable(state, guid, template)
        end

      _ ->
        if questgiver?(guid),
          do: Gossip.hello_game_object(state, guid),
          else: state |> Quests.credit_entity_interaction(guid) |> use_non_questgiver(guid)
    end
  end

  def use_quest_object(%{character: %Character{internal: %{world: world}}} = state, guid, world) do
    case GameObjectTemplateLoader.cached(Guid.entry(guid)) do
      %GameObjectTemplate{type: 10} = template -> use_readable(state, guid, template)
      _ -> state
    end
  end

  def use_quest_object(state, _guid, _world), do: state

  defp use_readable(%{character: character} = state, guid, template) do
    world = character.internal.world

    with true <- character.unit.health > 0,
         {^world, _, _, _} <- World.position(guid),
         %{go_spawned?: true, go_flags: flags} <- Metadata.get(guid),
         {:ok, character} <- GameObjectInteraction.prepare_readable_use(character, template, flags, Time.now()) do
      use_prepared_readable(state, character, guid, template)
    else
      _ -> state
    end
  end

  defp use_prepared_readable(state, character, guid, %GameObjectTemplate{type: 9, data: data}) do
    if Enum.at(data, 0, 0) > 0, do: Outbound.send_packet(%SmsgGameobjectPagetext{guid: guid})
    put_user(state, character)
  end

  defp use_prepared_readable(state, character, guid, %GameObjectTemplate{type: 10} = template) do
    goober = Goober.configuration(template)

    allowed? =
      Goober.quest_allowed?(character.player.quest_log, goober.quest_id, QuestLoader.get(goober.quest_id) != nil)

    result = Entity.call(guid, {:use_goober, character.object.guid, character.internal.world, allowed?})

    if result in [:activated, :read_only] do
      state = state |> put_user(character) |> show_readable(guid, goober)

      if result == :activated do
        InstanceSystem.game_object_used(character.internal.world, template.entry)
        Quests.credit_game_object_use(state, guid)
      else
        state
      end
    else
      state
    end
  end

  defp show_readable(state, guid, %{page_id: page_id}) when page_id > 0 do
    Outbound.send_packet(%SmsgGameobjectPagetext{guid: guid})
    state
  end

  defp show_readable(state, guid, %{gossip_id: gossip_id}) when gossip_id > 0,
    do: Gossip.hello_quest_object(state, guid, gossip_id)

  defp show_readable(state, _guid, _goober), do: state

  defp put_user(%{character: character} = state, character), do: state

  defp put_user(state, character) do
    character = character |> EventSink.emit_pending() |> CharacterStore.put()
    PlayerServer.maybe_broadcast_update(%{state | character: character})
  end

  defp battleground_use(%{character: character} = state, guid) do
    BattlegroundSystem.use_game_object(
      character.internal.world,
      state.guid,
      guid,
      Guid.entry(guid),
      character.movement_block.position
    )
  end

  defp use_non_questgiver(%{character: %Character{} = character} = state, guid) do
    Logger.info("CMSG_GAMEOBJ_USE: entry #{Guid.entry(guid)} chest?=#{chest?(guid)}")

    cond do
      fishing_bobber?(guid) ->
        Fishing.catch_fish(state, guid)

      chest?(guid) ->
        open_chest(state, guid)

      chair?(guid) ->
        sit_on_chair(state, guid)

      battleground_flag?(guid) ->
        use_battleground_flag(state, guid)

      true ->
        case BattlegroundSystem.use_game_object(
               character.internal.world,
               state.guid,
               guid,
               Guid.entry(guid),
               character.movement_block.position
             ) do
          :handled ->
            :ok

          :unhandled ->
            InstanceSystem.game_object_used(character.internal.world, Guid.entry(guid))
            Entity.use_game_object(guid, state.guid, character.unit.level)
        end

        state
    end
  end

  defp battleground_flag?(guid),
    do: match?(%GameObjectTemplate{type: type} when type in [24, 26], GameObjectTemplateLoader.cached(Guid.entry(guid)))

  defp use_battleground_flag(state, guid) do
    with true <- interactable?(state.character, guid),
         {:ok, character} <- GameObjectInteraction.prepare_battleground_use(state.character, Time.now()) do
      state = put_user(state, character)
      battleground_use(state, guid)
      state
    else
      _ineligible -> state
    end
  end

  defp questgiver?(guid) do
    Guid.type_id(guid) == :game_object and
      match?(%GameObjectTemplate{type: @go_type_questgiver}, GameObjectTemplateLoader.cached(Guid.entry(guid)))
  end

  defp fishing_bobber?(guid) do
    Guid.entity_type(guid) == :game_object and
      match?(%GameObjectTemplate{type: 17}, GameObjectTemplateLoader.get(Guid.entry(guid)))
  end

  defp chair?(guid) do
    Guid.entity_type(guid) == :game_object and
      match?(%GameObjectTemplate{type: @go_type_chair}, GameObjectTemplateLoader.get(Guid.entry(guid)))
  end

  defp sit_on_chair(%{character: %Character{internal: %{world: world}} = character} = state, guid) do
    with {^world, x, y, z} <- World.position(character),
         {:ok, position, stand_state} <- Entity.call(guid, {:chair_seat, world, {x, y, z}}) do
      character =
        character
        |> then(fn character -> %{character | unit: %{character.unit | stand_state: stand_state}} end)
        |> Effects.enqueue([Effects.teleport(position), Effects.stand_state(stand_state)])
        |> EventSink.emit_pending()

      %UpdateObject{update_type: :values, object_type: :player}
      |> struct(Map.from_struct(character))
      |> World.broadcast_packet(character, include_self?: false)

      %{state | character: character}
    else
      _error ->
        state
    end
  end

  def open_chest(state, guid), do: Looting.open(state, guid)

  def activate_object(state, guid, spell_id, range_yards) do
    case ObjectTarget.resolve(state, guid, range_yards) do
      {:ok, _template} -> state |> open_object(guid) |> Quests.credit_cast([guid], spell_id)
      {:error, _reason} -> state
    end
  end

  def chest?(guid) do
    Guid.entity_type(guid) == :game_object and
      match?(%GameObjectTemplate{type: @go_type_chest}, GameObjectTemplateLoader.get(Guid.entry(guid)))
  end
end
