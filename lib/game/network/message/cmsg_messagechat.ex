defmodule ThistleTea.Game.Network.Message.CmsgMessagechat do
  use ThistleTea.Game.Network.ClientMessage, :CMSG_MESSAGECHAT

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Item, as: DataItem
  alias ThistleTea.Game.Entity.Data.Quest
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.EquipmentStats
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.QuestLog
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.InventoryUpdate
  alias ThistleTea.Game.Player.Quests
  alias ThistleTea.Game.Player.Stats
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.ClassSpell
  alias ThistleTea.Game.World.Loader.Quest, as: QuestLoader
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Metadata

  require Logger

  defstruct [:chat_type, :language, :message, :target_name]

  @chat_type_say 0x0
  @chat_type_yell 0x5
  @chat_type_whisper 0x6
  @chat_type_emote 0x8
  @chat_type_channel 0x0E

  @say_range 25
  @yell_range 300
  @emote_range 25
  @speed_base 7.0
  @speed_min 0.1
  @speed_max 10.0

  def system_message(state, message) do
    Network.send_packet(%Message.SmsgMessagechat{
      chat_type: 0x0A,
      language: 0,
      sender_guid: state.guid,
      message: message,
      channel_name: nil,
      player_rank: 0,
      tag: 0
    })

    state
  end

  defp handle_additem(state, item_id_str, count_str) do
    with {item_id, ""} <- Integer.parse(item_id_str),
         {count, ""} when count > 0 <- Integer.parse(count_str) do
      give_item(state, item_id, count)
    else
      _ -> system_message(state, "Invalid command. Use: .additem <item_id> [count]")
    end
  end

  defp give_item(state, item_id, count) do
    case ItemStore.create(item_id, owner: state.guid, stack_count: count) do
      %DataItem{} = item ->
        case Inventory.store(state.character.player, state.guid, item, &ItemStore.get/1) do
          {:ok, result, placement} ->
            {bag_slot, item_slot} = finish_placement(item, placement)
            state = InventoryUpdate.apply(state, {:ok, result})

            Network.send_packet(%Message.SmsgItemPushResult{
              player_guid: state.guid,
              item_id: item_id,
              bag_slot: bag_slot,
              item_slot: item_slot,
              count: count,
              created: 1
            })

            state

          _ ->
            ItemStore.delete(item.object.guid)
            system_message(state, "Inventory full.")
        end

      _ ->
        system_message(state, "Item #{item_id} not found.")
    end
  end

  defp finish_placement(_item, {:placed, {bag, slot}, placed}) do
    ItemStore.put(placed)
    Network.send_packet(UpdateObject.from_item(placed))
    {bag, slot}
  end

  defp finish_placement(item, :merged) do
    ItemStore.delete(item.object.guid)
    {Inventory.bag_0(), 0xFFFFFFFF}
  end

  defp handle_addquest(state, quest_id_str) do
    with {quest_id, ""} <- Integer.parse(quest_id_str),
         %Quest{} = quest <- QuestLoader.get(quest_id) do
      case Quests.force_accept(state, quest_id) do
        %{character: %ThistleTea.Character{player: %{quest_log: quest_log}}} = state ->
          if QuestLog.active?(quest_log, quest_id) do
            system_message(state, "Added quest: #{quest.title} (#{quest_id})")
          else
            system_message(state, "Could not accept quest #{quest_id}.")
          end
      end
    else
      nil -> system_message(state, "Quest #{quest_id_str} not found.")
      _ -> system_message(state, "Invalid command. Use: .addquest <quest_id>")
    end
  end

  def teleport_player(state, x, y, z, map) do
    system_message(state, "Teleporting to #{x}, #{y}, #{z} on map #{map}")

    GenServer.cast(self(), {:start_teleport, x, y, z, map})

    state
  end

  defp parse_coords([x, y, z, map]) do
    with {x, _} <- Float.parse(x),
         {y, _} <- Float.parse(y),
         {z, _} <- Float.parse(z),
         {map, _} <- Integer.parse(map) do
      {:ok, x, y, z, map}
    else
      _ -> :error
    end
  end

  defp parse_coords([x, y, z]) do
    with {x, _} <- Float.parse(x),
         {y, _} <- Float.parse(y),
         {z, _} <- Float.parse(z) do
      {:ok, x, y, z}
    else
      _ -> :error
    end
  end

  def handle_chat(state, _, _, ".additem" <> params, _) do
    params
    |> String.split(" ", trim: true)
    |> case do
      [item_id] -> handle_additem(state, item_id, "1")
      [item_id, count] -> handle_additem(state, item_id, count)
      _ -> system_message(state, "Invalid command. Use: .additem <item_id> [count]")
    end
  end

  def handle_chat(state, _, _, ".addquest" <> params, _) do
    params
    |> String.split(" ", trim: true)
    |> case do
      [quest_id] -> handle_addquest(state, quest_id)
      _ -> system_message(state, "Invalid command. Use: .addquest <quest_id>")
    end
  end

  def handle_chat(state, _, _, ".help" <> _, _) do
    commands = [
      ".additem <item_id> [count] - add an item to your inventory",
      ".addquest <quest_id> - add a quest to your quest log",
      ".debug spells - learn class trainer spells up to your level",
      ".character level <level> - set player level",
      ".die - kill your character",
      ".go xyz <x> <y> <z> [map] - teleport",
      ".guid - show target guid",
      ".help - show help",
      ".learn <spell_id> - learn a spell",
      ".levelup [levels] - increase player level",
      ".modify hp <value> - set current health (clamped to max)",
      ".modify speed <rate> - modify player speed from 0.1 to 10",
      ".move - move target to you",
      ".pid - show target pid",
      ".pos - show current position",
      ".speed <rate> - modify player speed from 0.1 to 10",
      ".tgm - toggle god mode (no damage taken)"
    ]

    system_message(state, "Commands:")

    commands
    |> Enum.sort()
    |> Enum.reduce(state, fn command, acc ->
      system_message(acc, command)
    end)
  end

  def handle_chat(state, a, b, ".speed" <> rest, c) do
    handle_chat(state, a, b, ".modify speed" <> rest, c)
  end

  def handle_chat(state, _, _, ".character level" <> params, _) do
    params
    |> String.split(" ", trim: true)
    |> case do
      [level] -> handle_set_level(state, level)
      _ -> system_message(state, "Invalid command. Use: .character level <level>")
    end
  end

  def handle_chat(state, _, _, ".levelup" <> params, _) do
    params
    |> String.split(" ", trim: true)
    |> case do
      [] -> handle_levelup(state, "1")
      [levels] -> handle_levelup(state, levels)
      _ -> system_message(state, "Invalid command. Use: .levelup [levels]")
    end
  end

  def handle_chat(state, _, _, ".learn" <> params, _) do
    params
    |> String.split(" ", trim: true)
    |> case do
      [spell_id] -> handle_learn_spell(state, spell_id)
      _ -> system_message(state, "Invalid command. Use: .learn <spell_id>")
    end
  end

  def handle_chat(state, _, _, ".modify" <> params, _) do
    params
    |> String.split(" ", trim: true)
    |> case do
      ["speed", rate] ->
        handle_modify_speed(state, rate)

      ["hp", value] ->
        handle_modify_hp(state, value)

      _ ->
        Logger.error("Unhandled .modify call: #{params}")

        state
        |> system_message("Invalid command. Use: .modify <type> <n>")
    end
  end

  def handle_chat(state, _, _, ".debug spells" <> _, _) do
    state
    |> debug_spell_ids()
    |> then(&learn_spells(state, &1, "Already know all debug spells."))
  end

  def handle_chat(state, _, _, ".die" <> _, _) do
    %{character: %ThistleTea.Character{} = character} = state

    cond do
      not Death.alive?(character) ->
        system_message(state, "Already dead.")

      character.internal.godmode ->
        system_message(state, "Disable god mode first (.tgm).")

      true ->
        character = Core.take_damage(character, character.unit.health, ThistleTea.Game.Time.now())

        state
        |> put_character(character)
        |> system_message("You died.")
    end
  end

  def handle_chat(state, _, _, ".tgm" <> _, _) do
    %{character: %ThistleTea.Character{internal: internal} = character} = state
    new_godmode = not (internal.godmode || false)
    character = %{character | internal: %{internal | godmode: new_godmode}}

    state
    |> Map.put(:character, character)
    |> system_message("God mode #{if new_godmode, do: "ON", else: "OFF"}.")
  end

  def handle_chat(state, _, _, ".pos" <> _, _) do
    {x, y, z, _o} = state.character.movement_block.position
    map = state.character.internal.map

    state
    |> system_message("#{x} #{y} #{z} #{map}")
  end

  def handle_chat(state, _, _, ".guid" <> _, _) do
    state
    |> system_message("Target GUID: #{state.target}")
  end

  def handle_chat(state, _, _, ".pid" <> _, _) do
    case Entity.pid(state.target) do
      pid when is_pid(pid) ->
        state
        |> system_message("Target PID: #{inspect(pid)}")

      _ ->
        state
        |> system_message("No PID found.")
    end
  end

  def handle_chat(state, _, _, ".go xyz " <> rest, _) do
    rest
    |> String.split(" ", trim: true)
    |> parse_coords()
    |> case do
      {:ok, x, y, z, map} -> teleport_player(state, x, y, z, map)
      {:ok, x, y, z} -> teleport_player(state, x, y, z, state.character.internal.map)
      :error -> system_message(state, "Invalid command. Use: .go xyz <x> <y> <z> [map]")
    end
  end

  def handle_chat(state, _, _, ".move" <> _, _) do
    target = Map.get(state, :target)

    case state.character.movement_block.position do
      {x, y, z, _o} ->
        Entity.move_to(target, {x, y, z})
        state

      _ ->
        state
    end
  end

  def handle_chat(state, chat_type, language, message, _target_name)
      when chat_type in [@chat_type_say, @chat_type_yell, @chat_type_emote] do
    range =
      case chat_type do
        @chat_type_say -> @say_range
        @chat_type_yell -> @yell_range
        @chat_type_emote -> @emote_range
      end

    %Message.SmsgMessagechat{
      chat_type: chat_type,
      language: language,
      sender_guid: state.guid,
      message: message,
      channel_name: nil,
      player_rank: 0,
      tag: 0
    }
    |> World.broadcast_packet(state.character, range: range)

    state
  end

  def handle_chat(state, @chat_type_whisper, language, message, target_name) do
    case Metadata.find_guid_by(:name, target_name) do
      guid when is_integer(guid) ->
        message = %Message.SmsgMessagechat{
          chat_type: @chat_type_whisper,
          language: language,
          sender_guid: state.guid,
          message: message,
          channel_name: nil,
          player_rank: 0,
          tag: 0
        }

        case Network.send_packet(message, guid) do
          :ok ->
            :ok

          _ ->
            %Message.SmsgChatPlayerNotFound{name: target_name}
            |> Network.send_packet()
        end

      _ ->
        %Message.SmsgChatPlayerNotFound{name: target_name}
        |> Network.send_packet()
    end

    state
  end

  def handle_chat(state, @chat_type_channel, language, message, target_name) do
    message = %Message.SmsgMessagechat{
      chat_type: @chat_type_channel,
      language: language,
      sender_guid: state.guid,
      message: message,
      channel_name: target_name,
      player_rank: 0,
      tag: 0
    }

    ThistleTea.ChatChannel
    |> Registry.dispatch(target_name, fn entries ->
      for {pid, _} <- entries do
        Network.send_packet(message, pid)
      end
    end)

    state
  end

  def handle_chat(state, chat_type, language, message, target_name) do
    Logger.error("Unhandled chat type: #{chat_type}")

    message = %Message.SmsgMessagechat{
      chat_type: chat_type,
      language: language,
      sender_guid: state.guid,
      message: message,
      channel_name: target_name,
      player_rank: 0,
      tag: 0
    }

    all_players =
      :ets.tab2list(:players)
      |> Enum.map(fn {_, guid} -> guid end)

    for guid <- all_players do
      Network.send_packet(message, guid)
    end

    state
  end

  defp handle_modify_speed(state, rate) do
    case Float.parse(rate) do
      {rate, _} when rate >= @speed_min and rate <= @speed_max ->
        {target, guid} = resolve_speed_target(state)
        speed = rate * @speed_base

        %Message.SmsgForceRunSpeedChange{guid: guid, speed: speed}
        |> Network.send_packet(target)

        state
        |> system_message("Speed set to #{rate}")

      _ ->
        state
        |> system_message("Invalid speed. Use: .modify speed <rate 0.1 - 10.0>")
    end
  end

  defp handle_modify_hp(%{character: %ThistleTea.Character{unit: %Unit{} = unit} = character} = state, value) do
    case parse_positive_integer(value) do
      {:ok, hp} ->
        hp = min(hp, unit.max_health || hp)
        character = %{character | unit: %{unit | health: hp}}

        state
        |> put_character(character)
        |> system_message("Health set to #{hp}.")

      _ ->
        system_message(state, "Invalid command. Use: .modify hp <value>")
    end
  end

  defp handle_set_level(%{character: %ThistleTea.Character{}} = state, level) do
    with {:ok, level} <- parse_positive_integer(level),
         {:ok, character, level_up} <- set_character_level(state.character, level) do
      state
      |> maybe_send_level_up(level_up)
      |> put_character(character)
      |> system_message("Level set to #{character.unit.level}.")
    else
      _ -> system_message(state, "Invalid level.")
    end
  end

  defp handle_levelup(%{character: %ThistleTea.Character{unit: %{level: level}}} = state, levels) do
    with {:ok, levels} <- parse_positive_integer(levels),
         {:ok, character, level_up} <- set_character_level(state.character, level + levels) do
      state
      |> maybe_send_level_up(level_up)
      |> put_character(character)
      |> system_message("Level set to #{character.unit.level}.")
    else
      _ -> system_message(state, "Invalid level count.")
    end
  end

  defp handle_learn_spell(state, spell_id) do
    case parse_positive_integer(spell_id) do
      {:ok, spell_id} -> learn_spells(state, [spell_id], "Already know spell #{spell_id}.")
      :error -> system_message(state, "Invalid spell id.")
    end
  end

  defp set_character_level(%ThistleTea.Character{} = character, level) do
    level = min(level, Stats.max_level())
    old_stats = Stats.from_character(character)

    case Stats.get(character.unit.race, character.unit.class, level) do
      {:ok, new_stats} ->
        character =
          character
          |> EquipmentStats.remove()
          |> Stats.apply(new_stats)
          |> ThistleTea.Character.sync_equipment_stats()
          |> ThistleTea.Character.restore_health_and_mana()
          |> put_player_xp(0)

        level_up =
          if new_stats.level > old_stats.level do
            Stats.level_delta(old_stats, new_stats)
          end

        {:ok, character, level_up}

      _ ->
        :error
    end
  end

  defp put_player_xp(%ThistleTea.Character{player: player} = character, xp) do
    %{character | player: %{player | xp: xp}}
  end

  defp put_character(%{guid: guid} = state, %ThistleTea.Character{} = character) do
    ThistleTea.Character.save(character)

    Metadata.update(guid, %{
      level: character.unit.level,
      alive?: Death.alive?(character),
      ghost?: Death.ghost?(character)
    })

    update = Core.update_object(character, :values)
    Network.send_packet(update)
    World.broadcast_packet(update, character, include_self?: false)

    %{state | character: character}
  end

  defp maybe_send_level_up(state, nil), do: state

  defp maybe_send_level_up(state, level_up) when is_map(level_up) do
    Network.send_packet(struct(Message.SmsgLevelupInfo, level_up))
    state
  end

  defp learn_spells(
         %{character: %ThistleTea.Character{internal: internal} = character} = state,
         spell_ids,
         known_message
       ) do
    existing_ids = MapSet.new(internal.spells || [])
    new_ids = Enum.reject(spell_ids, &MapSet.member?(existing_ids, &1))

    case new_ids do
      [] ->
        system_message(state, known_message)

      _ ->
        all_ids = (internal.spells || []) ++ new_ids
        spellbook = SpellLoader.build_spellbook(all_ids)

        character = %{character | internal: %{internal | spells: all_ids, spellbook: spellbook}}
        ThistleTea.Character.save(character)

        for id <- new_ids do
          Network.send_packet(%Message.SmsgLearnedSpell{spell_id: id})
        end

        names =
          new_ids
          |> Enum.map_join(", ", fn id ->
            case Map.get(spellbook, id) do
              %{name: name} -> name
              _ -> "spell #{id}"
            end
          end)

        state
        |> Map.put(:character, character)
        |> system_message("Learned: #{names}")
    end
  end

  defp debug_spell_ids(%{character: %ThistleTea.Character{unit: %{class: class, level: level}}}) do
    ClassSpell.trainable_spell_ids(class, level)
  end

  defp debug_spell_ids(_state), do: []

  defp parse_positive_integer(value) do
    case Integer.parse(value) do
      {value, ""} when value > 0 -> {:ok, value}
      _ -> :error
    end
  end

  defp resolve_speed_target(state) do
    target_guid = Map.get(state, :target)

    cond do
      not is_integer(target_guid) ->
        {self(), state.guid}

      target_guid == state.guid ->
        {self(), state.guid}

      true ->
        if Guid.entity_type(target_guid) == :player and Entity.online?(target_guid) do
          {target_guid, target_guid}
        else
          {self(), state.guid}
        end
    end
  end

  @impl ClientMessage
  def handle(%__MODULE__{chat_type: chat_type, language: language, message: message, target_name: target_name}, state) do
    handle_chat(state, chat_type, language, message, target_name)
  end

  @impl ClientMessage
  def from_binary(payload) do
    <<chat_type::little-size(32), language::little-size(32), rest::binary>> = payload

    {target_name, rest} =
      if chat_type in [@chat_type_whisper, @chat_type_channel] do
        {:ok, target_name, rest} = BinaryUtils.parse_string(rest)
        {target_name, rest}
      else
        {nil, rest}
      end

    {:ok, message, _rest} = BinaryUtils.parse_string(rest)

    %__MODULE__{
      chat_type: chat_type,
      language: language,
      message: message,
      target_name: target_name
    }
  end
end
