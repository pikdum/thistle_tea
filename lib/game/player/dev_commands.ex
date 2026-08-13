defmodule ThistleTea.Game.Player.DevCommands do
  @moduledoc """
  Dot-command interpreter for debug chat commands (`.additem`, `.go xyz`,
  `.tgm`, …): parses the command, applies it to the player session, and
  replies with system chat messages. `run/2` returns `:unhandled` for
  anything that isn't a known command so normal chat can proceed.
  """
  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Data.Quest
  alias ThistleTea.Game.Entity.Data.Reputation.Definition
  alias ThistleTea.Game.Entity.Data.Reputation.State, as: ReputationState
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.Condition.InstanceDataSnapshot, as: Snapshot
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.MovementStats
  alias ThistleTea.Game.Entity.Logic.Proficiency
  alias ThistleTea.Game.Entity.Logic.QuestLog
  alias ThistleTea.Game.Entity.Logic.Reputation, as: ReputationLogic
  alias ThistleTea.Game.Entity.Logic.Rest
  alias ThistleTea.Game.Entity.Logic.Skills
  alias ThistleTea.Game.Entity.Server.Player, as: PlayerServer
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.Player.Battlegrounds, as: PlayerBattlegrounds
  alias ThistleTea.Game.Player.Characters
  alias ThistleTea.Game.Player.Exploration, as: PlayerExploration
  alias ThistleTea.Game.Player.Items
  alias ThistleTea.Game.Player.Quests
  alias ThistleTea.Game.Player.Reputation, as: PlayerReputation
  alias ThistleTea.Game.Player.Spells
  alias ThistleTea.Game.Player.Stats
  alias ThistleTea.Game.Player.Talents
  alias ThistleTea.Game.Player.Taxi, as: PlayerTaxi
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.InstanceData
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.ClassSpell
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader
  alias ThistleTea.Game.World.Loader.Quest, as: QuestLoader
  alias ThistleTea.Game.World.Loader.Reputation, as: ReputationLoader
  alias ThistleTea.Game.World.Loader.Skill, as: SkillLoader
  alias ThistleTea.Game.World.Loader.Taxi, as: TaxiLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.PostOffice
  alias ThistleTea.Game.World.System.Battleground, as: BattlegroundSystem
  alias ThistleTea.Game.World.System.GameEvent
  alias ThistleTea.Game.World.System.Instance, as: InstanceSystem
  alias ThistleTea.Game.World.Transports
  alias ThistleTea.Game.WorldRef

  require Logger

  @speed_min 0.1
  @speed_max 10.0
  @max_coinage 0x7FFFFFFF
  @warsong_gulch_map_id 489

  def run(state, ".additem" <> params) do
    params
    |> String.split(" ", trim: true)
    |> case do
      [item_id] -> additem(state, item_id, "1")
      [item_id, count] -> additem(state, item_id, count)
      _ -> system_message(state, "Invalid command. Use: .additem <item_id> [count]")
    end
    |> handled()
  end

  def run(state, ".talents reset" <> _) do
    state = Talents.reset(state)

    state
    |> system_message("Talents reset.")
    |> handled()
  end

  def run(state, ".addquest" <> params) do
    params
    |> String.split(" ", trim: true)
    |> case do
      [quest_id] -> addquest(state, quest_id)
      _ -> system_message(state, "Invalid command. Use: .addquest <quest_id>")
    end
    |> handled()
  end

  def run(state, ".mail" <> params) do
    params
    |> String.split(~r/\s+/, parts: 2, trim: true)
    |> case do
      [recipient, body] when byte_size(body) <= 500 -> send_mail(state, recipient, body)
      _ -> system_message(state, "Invalid command. Use: .mail <recipient> <message>")
    end
    |> handled()
  end

  def run(state, ".help" <> _) do
    commands = [
      ".additem <item_id> [count] - add an item to your inventory",
      ".addquest <quest_id> - add a quest to your quest log",
      ".debug random equipment - add a random player-obtainable equipment set",
      ".debug professions - set known professions to 300/300",
      ".debug position <guid> - show an entity's projected world position",
      ".debug reputation <faction_id> - show standing and flags",
      ".debug reputation add <faction_id> <delta> - change standing",
      ".debug reputation find <name> - find faction ids",
      ".debug reputation set <faction_id> <standing> - set absolute standing",
      ".debug reputation war <faction_id> <on|off> - toggle at-war",
      ".debug skills - max out known skills for your level",
      ".debug spells - learn class trainer spells up to your level",
      ".debug events - show active events and the next scheduled change",
      ".debug explore - unlock every world-map area",
      ".debug taxi - unlock every flight path",
      ".debug transport - show the attached or nearest transport",
      ".debug transport list - list active transports on this map",
      ".debug transport advance <seconds> [entry] - advance a transport schedule",
      ".character level <level> - set player level",
      ".die - kill your character",
      ".go xyz <x> <y> <z> [map] - teleport",
      ".guid - show target guid",
      ".help - show help",
      ".instance info - show instance ownership and membership",
      ".instance data [field] - show read-only instance script data",
      ".instance reset - reset empty owned instances",
      ".instance switch <id> - join a copy of the current map",
      ".learn <spell_id> - learn a spell",
      ".levelup [levels] - increase player level",
      ".mail <recipient> <message> - send an immediate debug letter",
      ".modify hp <value> - set current health (clamped to max)",
      ".modify money <copper> - add money (negative to remove)",
      ".modify rage <value> - set current rage (clamped to max)",
      ".modify speed <rate> - modify player speed from 0.1 to 10",
      ".move - move target to you",
      ".pid - show target pid",
      ".pos - show current position",
      ".talents reset - unlearn all talents and refund points",
      ".rested [amount] - add rested xp",
      ".speed <rate> - modify player speed from 0.1 to 10",
      ".tgm - toggle god mode (no damage taken)",
      ".threat - show the targeted mob's threat table"
    ]

    system_message(state, "Commands:")

    commands
    |> Enum.sort()
    |> Enum.reduce(state, fn command, acc ->
      system_message(acc, command)
    end)
    |> handled()
  end

  def run(state, ".speed" <> rest) do
    run(state, ".modify speed" <> rest)
  end

  def run(state, ".rested" <> params) do
    params
    |> String.split()
    |> case do
      [] -> add_rested(state, "1000")
      [amount] -> add_rested(state, amount)
      _ -> system_message(state, "Invalid command. Use: .rested [amount]")
    end
    |> handled()
  end

  def run(state, ".character level" <> params) do
    params
    |> String.split(" ", trim: true)
    |> case do
      [level] -> set_level(state, level)
      _ -> system_message(state, "Invalid command. Use: .character level <level>")
    end
    |> handled()
  end

  def run(state, ".levelup" <> params) do
    params
    |> String.split(" ", trim: true)
    |> case do
      [] -> levelup(state, "1")
      [levels] -> levelup(state, levels)
      _ -> system_message(state, "Invalid command. Use: .levelup [levels]")
    end
    |> handled()
  end

  def run(state, ".learn" <> params) do
    params
    |> String.split(" ", trim: true)
    |> case do
      [spell_id] -> learn_spell(state, spell_id)
      _ -> system_message(state, "Invalid command. Use: .learn <spell_id>")
    end
    |> handled()
  end

  def run(state, ".modify" <> params) do
    params
    |> String.split(" ", trim: true)
    |> case do
      ["speed", rate] ->
        modify_speed(state, rate)

      ["hp", value] ->
        modify_hp(state, value)

      ["rage", value] ->
        modify_rage(state, value)

      ["money", value] ->
        modify_money(state, value)

      _ ->
        Logger.error("Unhandled .modify call: #{params}")

        state
        |> system_message("Invalid command. Use: .modify <type> <n>")
    end
    |> handled()
  end

  def run(state, ".debug spells" <> _) do
    state
    |> debug_spell_ids()
    |> then(&learn_spells(state, &1, "Already know all debug spells."))
    |> handled()
  end

  def run(state, ".debug reputation" <> params) do
    params
    |> String.split(" ", trim: true)
    |> debug_reputation(state)
    |> handled()
  end

  def run(state, ".debug position" <> params) do
    params
    |> String.split(" ", trim: true)
    |> case do
      [guid] -> show_entity_position(state, guid)
      _invalid -> system_message(state, "Invalid command. Use: .debug position <guid>")
    end
    |> handled()
  end

  def run(state, ".debug events" <> _) do
    %{active: active, next: next} = GameEvent.status()

    state
    |> system_message("Active events: #{event_labels(active)}")
    |> system_message(next_event_message(next))
    |> handled()
  end

  def run(state, ".debug explore" <> _) do
    state
    |> PlayerExploration.unlock_all()
    |> system_message("World map fully explored.")
    |> handled()
  end

  def run(state, ".debug taxi" <> _) do
    state
    |> PlayerTaxi.unlock_all(TaxiLoader.get())
    |> system_message("All flight paths unlocked.")
    |> handled()
  end

  def run(state, ".debug skills" <> _) do
    state
    |> max_skills()
    |> handled()
  end

  def run(state, ".debug professions" <> _) do
    state
    |> max_professions()
    |> handled()
  end

  def run(state, ".debug random equipment" <> _) do
    state
    |> add_random_equipment()
    |> handled()
  end

  def run(state, ".debug transport" <> params) do
    params
    |> String.split(" ", trim: true)
    |> case do
      [] -> show_transport(state)
      ["status"] -> show_transport(state)
      ["list"] -> list_transports(state)
      ["advance", seconds] -> advance_transport(state, seconds, nil)
      ["advance", seconds, entry] -> advance_transport(state, seconds, entry)
      _ -> transport_usage(state)
    end
    |> handled()
  end

  def run(state, ".die" <> _) do
    %{character: %Character{} = character} = state

    cond do
      not Death.alive?(character) ->
        system_message(state, "Already dead.")

      character.internal.godmode ->
        system_message(state, "Disable god mode first (.tgm).")

      true ->
        character = Core.take_damage(character, character.unit.health, Time.now())

        state
        |> put_character(character)
        |> system_message("You died.")
    end
    |> handled()
  end

  def run(state, ".tgm" <> _) do
    %{character: %Character{internal: internal} = character} = state
    new_godmode = not (internal.godmode || false)
    character = %{character | internal: %{internal | godmode: new_godmode}}

    state
    |> Map.put(:character, character)
    |> system_message("God mode #{if new_godmode, do: "ON", else: "OFF"}.")
    |> handled()
  end

  def run(state, ".pos" <> _) do
    {x, y, z, _o} = state.character.movement_block.position
    map = state.character.internal.world.map_id

    state
    |> system_message("#{x} #{y} #{z} #{map}")
    |> handled()
  end

  def run(state, ".guid" <> _) do
    state
    |> system_message("Target GUID: #{state.target}")
    |> handled()
  end

  def run(state, ".threat" <> _) do
    state
    |> show_threat()
    |> handled()
  end

  def run(state, ".pid" <> _) do
    case Entity.pid(state.target) do
      pid when is_pid(pid) ->
        state
        |> system_message("Target PID: #{inspect(pid)}")

      _ ->
        state
        |> system_message("No PID found.")
    end
    |> handled()
  end

  def run(state, ".go xyz " <> rest) do
    rest
    |> String.split(" ", trim: true)
    |> parse_coords()
    |> case do
      {:ok, x, y, z, map} -> teleport_player(state, x, y, z, map)
      {:ok, x, y, z} -> teleport_player(state, x, y, z, state.character.internal.world)
      :error -> system_message(state, "Invalid command. Use: .go xyz <x> <y> <z> [map]")
    end
    |> handled()
  end

  def run(state, ".battleground" <> params) do
    state
    |> battleground_command(String.split(params, " ", trim: true))
    |> handled()
  end

  def run(state, ".bg" <> params), do: run(state, ".battleground" <> params)

  def run(state, ".instance info" <> _) do
    info = InstanceSystem.info(state.guid)
    world = state.character.internal.world

    state
    |> system_message("World: #{world_label(world)}")
    |> system_message("Owner: #{owner_label(info.owner)}")
    |> system_message("Tracked copy: #{world_label(info.current)}")
    |> system_message("Owned copies: #{copies_label(info.copies)}")
    |> handled()
  end

  def run(state, ".instance data" <> params) do
    state
    |> show_instance_data(String.split(params, " ", trim: true))
    |> handled()
  end

  def run(state, ".instance reset" <> _) do
    state
    |> reset_instances()
    |> handled()
  end

  def run(state, ".instance switch " <> instance_id) do
    state
    |> switch_instance(instance_id)
    |> handled()
  end

  def run(state, ".move" <> _) do
    target = Map.get(state, :target)

    case state.character.movement_block.position do
      {x, y, z, _o} ->
        Entity.move_to(target, {x, y, z})
        state

      _ ->
        state
    end
    |> handled()
  end

  def run(_state, _message), do: :unhandled

  defp handled(state), do: {:handled, state}

  defp show_threat(%{target: target} = state) when is_integer(target) and target > 0 do
    with :mob <- Guid.entity_type(target),
         {:ok, %{victim: victim, entries: entries}} <- Entity.call(target, :threat_table) do
      print_threat_table(state, target, victim, entries)
    else
      {:error, _reason} -> system_message(state, "Target is not an active mob.")
      _other -> system_message(state, "Target is not a mob.")
    end
  end

  defp show_threat(state), do: system_message(state, "No target selected.")

  defp print_threat_table(state, target, victim, entries) do
    state = system_message(state, "Threat table for #{entity_name(target)}:")

    case entries do
      [] ->
        system_message(state, "  (empty)")

      entries ->
        Enum.reduce(entries, state, fn entry, acc ->
          system_message(acc, threat_line(entry, victim))
        end)
    end
  end

  defp threat_line({guid, threat}, victim) do
    marker = if guid == victim, do: " <- victim", else: ""
    "  #{entity_name(guid)}: #{Float.round(threat / 1, 1)}#{marker}"
  end

  defp entity_name(guid) do
    case Metadata.query(guid, [:name]) do
      %{name: name} when is_binary(name) -> name
      _ -> "guid #{guid}"
    end
  end

  defp debug_reputation([], state), do: reputation_usage(state)

  defp debug_reputation(["find" | words], state) when words != [] do
    query = words |> Enum.join(" ") |> String.downcase()

    matches =
      ReputationLoader.catalog().factions
      |> Map.values()
      |> Enum.filter(&String.contains?(String.downcase(&1.name || ""), query))
      |> Enum.sort_by(& &1.name)
      |> Enum.take(15)

    case matches do
      [] ->
        system_message(state, "No reputation factions match #{inspect(Enum.join(words, " "))}.")

      matches ->
        Enum.reduce(matches, state, fn definition, state ->
          system_message(state, "#{definition.name} (#{definition.id}), slot #{definition.index}")
        end)
    end
  end

  defp debug_reputation(["set", faction_id, standing], state) do
    with {:ok, faction_id} <- parse_positive_integer(faction_id),
         {standing, ""} <- Integer.parse(standing),
         %Definition{} <- ReputationLoader.faction(faction_id) do
      state
      |> PlayerReputation.set(faction_id, standing)
      |> reputation_status(faction_id)
    else
      _ -> reputation_usage(state)
    end
  end

  defp debug_reputation(["add", faction_id, delta], state) do
    with {:ok, faction_id} <- parse_positive_integer(faction_id),
         {delta, ""} <- Integer.parse(delta),
         %Definition{} <- ReputationLoader.faction(faction_id) do
      state
      |> PlayerReputation.modify(faction_id, delta)
      |> reputation_status(faction_id)
    else
      _ -> reputation_usage(state)
    end
  end

  defp debug_reputation(["war", faction_id, enabled], state) when enabled in ["on", "off"] do
    with {:ok, faction_id} <- parse_positive_integer(faction_id),
         %Definition{index: index} <- ReputationLoader.faction(faction_id) do
      state
      |> PlayerReputation.set_at_war(index, enabled == "on", notify?: true)
      |> reputation_status(faction_id)
    else
      _ -> reputation_usage(state)
    end
  end

  defp debug_reputation([faction_id], state) do
    with {:ok, faction_id} <- parse_positive_integer(faction_id),
         %Definition{} <- ReputationLoader.faction(faction_id) do
      reputation_status(state, faction_id)
    else
      _ -> reputation_usage(state)
    end
  end

  defp debug_reputation(_params, state), do: reputation_usage(state)

  defp reputation_status(%{character: %Character{} = character} = state, faction_id) do
    definition = ReputationLoader.faction(faction_id)
    reputation_state = ReputationLogic.state(character.player.reputation, faction_id)
    standing = PlayerReputation.standing(character, faction_id)
    rank = ReputationLogic.rank(standing)

    system_message(
      state,
      "#{definition.name} (#{faction_id}), slot #{definition.index}: #{standing}, " <>
        "#{rank_label(rank)}, flags #{reputation_flags(reputation_state)}"
    )
  end

  defp reputation_usage(state) do
    system_message(
      state,
      "Use: .debug reputation <faction_id>|find <name>|set <faction_id> <standing>|" <>
        "add <faction_id> <delta>|war <faction_id> <on|off>"
    )
  end

  defp reputation_flags(%ReputationState{flags: flags}) do
    [
      {0x01, "visible"},
      {0x02, "at-war"},
      {0x04, "hidden"},
      {0x08, "forced-invisible"},
      {0x10, "peace-forced"},
      {0x20, "inactive"}
    ]
    |> Enum.flat_map(fn {flag, label} -> if Bitwise.band(flags, flag) == 0, do: [], else: [label] end)
    |> case do
      [] -> "none"
      labels -> Enum.join(labels, ",")
    end
  end

  defp reputation_flags(nil), do: "none"

  defp rank_label(rank) do
    rank
    |> Atom.to_string()
    |> String.capitalize()
  end

  defp additem(state, item_id_str, count_str) do
    with {item_id, ""} <- Integer.parse(item_id_str),
         {count, ""} when count > 0 <- Integer.parse(count_str) do
      Items.give(state, item_id, count)
    else
      _ -> system_message(state, "Invalid command. Use: .additem <item_id> [count]")
    end
  end

  defp addquest(state, quest_id_str) do
    with {quest_id, ""} <- Integer.parse(quest_id_str),
         %Quest{} = quest <- QuestLoader.get(quest_id) do
      case Quests.force_accept(state, quest_id) do
        %{character: %Character{player: %{quest_log: quest_log}}} = state ->
          # credo:disable-for-next-line Credo.Check.Refactor.Nesting
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

  defp send_mail(state, recipient_name, body) do
    recipient_name = String.capitalize(String.downcase(recipient_name))

    case CharacterStore.get_by_name(recipient_name) do
      %Character{} = recipient -> post_debug_mail(state, recipient, body)
      nil -> system_message(state, "Character #{recipient_name} not found.")
    end
  end

  defp post_debug_mail(state, %Character{} = recipient, body) do
    attrs = %{
      sender: state.guid,
      sender_type: :normal,
      receiver: recipient.object.guid,
      subject: "Debug mail",
      body: body
    }

    case PostOffice.post(attrs) do
      {:ok, _mail} -> system_message(state, "Mail sent to #{recipient.internal.name}.")
      {:error, _reason} -> system_message(state, "Could not send mail.")
    end
  end

  defp teleport_player(state, x, y, z, map) do
    system_message(state, "Teleporting to #{x}, #{y}, #{z} on #{destination_label(map)}")

    GenServer.cast(self(), {:start_teleport, x, y, z, map})

    state
  end

  defp battleground_command(state, ["join"]), do: battleground_command(state, ["join", "warsong"])

  defp battleground_command(state, ["join", "warsong"]) do
    case PlayerBattlegrounds.debug_join_solo(state, @warsong_gulch_map_id) do
      {:ok, state} ->
        system_message(state, "Solo Warsong Gulch invitation created. Click Enter Battle.")

      {:error, reason, state} ->
        system_message(state, battleground_error(reason))
    end
  end

  defp battleground_command(state, ["start"]) do
    case PlayerBattlegrounds.debug_start_now(state) do
      {:ok, state} -> system_message(state, "Warsong Gulch started; gates opened.")
      {:error, reason, state} -> system_message(state, battleground_error(reason))
    end
  end

  defp battleground_command(state, ["info"]) do
    state.guid
    |> BattlegroundSystem.debug_info()
    |> battleground_info_message()
    |> then(&system_message(state, &1))
  end

  defp battleground_command(state, ["leave"]) do
    case PlayerBattlegrounds.debug_leave(state) do
      {:ok, state} -> system_message(state, "Left the battleground queue or match.")
      {:error, reason, state} -> system_message(state, battleground_error(reason))
    end
  end

  defp battleground_command(state, _params) do
    system_message(state, "Invalid command. Use: .battleground <join [warsong]|start|info|leave>")
  end

  defp battleground_info_message(%{status: :none}), do: "Battleground: none."

  defp battleground_info_message(%{status: :wait_queue, map_id: map_id, bracket: bracket}) do
    "Battleground: queued for map #{map_id}, bracket #{bracket}."
  end

  defp battleground_info_message(info) do
    scores = "#{info.scores.alliance}-#{info.scores.horde}"
    teams = "#{info.players.alliance} Alliance / #{info.players.horde} Horde / #{info.players.inside} inside"
    flags = "Alliance #{info.flags.alliance}, Horde #{info.flags.horde}"

    "Battleground: #{info.status}, #{world_label(info.world)}, phase #{info.phase}, score #{scores}, players #{teams}, flags #{flags}."
  end

  defp battleground_error(:already_queued), do: "You are already queued or matched."
  defp battleground_error(:level_restricted), do: "Your level is outside the Warsong Gulch range."
  defp battleground_error(:unsupported_battleground), do: "Warsong Gulch data is not loaded."
  defp battleground_error(:not_counting_down), do: "The battleground is not counting down."
  defp battleground_error(:not_in_battleground), do: "You are not in a battleground."
  defp battleground_error(:not_ready), do: "Your player session is not ready."
  defp battleground_error(_reason), do: "The battleground debug command could not be completed."

  defp destination_label(%WorldRef{} = world), do: world_label(world)
  defp destination_label(map_id) when is_integer(map_id), do: "map #{map_id}"

  defp reset_instances(state) do
    case InstanceSystem.reset(state.guid) do
      {:ok, %{reset: reset, failed: failed}} ->
        state
        |> system_message("Reset copies: #{worlds_label(reset)}")
        |> system_message("Occupied copies: #{worlds_label(failed)}")

      {:error, :not_leader} ->
        system_message(state, "Only the party leader can reset instances.")
    end
  end

  defp show_instance_data(state, []) do
    state.character.internal.world
    |> InstanceData.read_all()
    |> instance_data_message()
    |> then(&system_message(state, &1))
  end

  defp show_instance_data(state, [field]) do
    case Integer.parse(field) do
      {field, ""} when field >= 0 ->
        state.character.internal.world
        |> InstanceData.read([field])
        |> instance_data_message()
        |> then(&system_message(state, &1))

      _invalid ->
        system_message(state, "Invalid command. Use: .instance data [field]")
    end
  end

  defp show_instance_data(state, _params) do
    system_message(state, "Invalid command. Use: .instance data [field]")
  end

  defp instance_data_message(%Snapshot{status: :available, fields: fields, script_name: script_name}) do
    values =
      fields
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map_join(", ", fn
        {field, {:ok, value}} -> "#{field}=#{value}"
        {field, {:error, {:unsupported_field, unsupported}}} when unsupported == field -> "#{field}=unsupported"
        {field, {:error, _reason}} -> "#{field}=unknown"
      end)

    "Instance data (#{script_name}): #{values}"
  end

  defp instance_data_message(%Snapshot{status: :no_instance_script}), do: "Current map has no instance script."
  defp instance_data_message(%Snapshot{status: :open_world}), do: "Current world is not an instance copy."
  defp instance_data_message(%Snapshot{status: :missing_copy}), do: "Instance copy is no longer active."

  defp instance_data_message(%Snapshot{status: {:unsupported_script, script_name}}) do
    "Instance script #{script_name} has no registered fields."
  end

  defp switch_instance(state, instance_id) do
    with {:ok, instance_id} <- parse_positive_integer(String.trim(instance_id)),
         world = WorldRef.instance(state.character.internal.world.map_id, instance_id),
         :ok <- InstanceSystem.switch(state.guid, world) do
      {x, y, z, orientation} = state.character.movement_block.position
      GenServer.cast(self(), {:start_teleport, x, y, z, orientation, world})
      system_message(state, "Switching to #{world_label(world)}.")
    else
      {:error, :not_found} -> system_message(state, "Instance copy not found.")
      _invalid -> system_message(state, "Invalid command. Use: .instance switch <id>")
    end
  end

  defp copies_label([]), do: "none"

  defp copies_label(copies) do
    Enum.map_join(copies, ", ", fn copy ->
      "#{world_label(copy.world)} (#{length(copy.members)} inside)"
    end)
  end

  defp worlds_label([]), do: "none"
  defp worlds_label(worlds), do: Enum.map_join(worlds, ", ", &world_label/1)

  defp world_label(nil), do: "none"
  defp world_label(%WorldRef{map_id: map_id, instance_id: nil}), do: "map #{map_id} / open"

  defp world_label(%WorldRef{map_id: map_id, instance_id: instance_id}) do
    "map #{map_id} / instance #{instance_id}"
  end

  defp show_entity_position(state, guid_text) do
    with {guid, ""} when guid > 0 <- Integer.parse(guid_text),
         {%WorldRef{} = world, x, y, z} <- World.position(guid) do
      orientation =
        case Metadata.query(guid, [:orientation]) do
          %{orientation: orientation} when is_number(orientation) -> orientation
          _missing -> "unknown"
        end

      system_message(
        state,
        "Entity #{guid}: #{world_label(world)}, position #{x} #{y} #{z}, orientation #{orientation}"
      )
    else
      {_guid, _rest} -> system_message(state, "Invalid command. Use: .debug position <guid>")
      :error -> system_message(state, "Invalid command. Use: .debug position <guid>")
      nil -> system_message(state, "Entity #{guid_text} is inactive or missing.")
    end
  end

  defp owner_label({:party, id}), do: "party #{id}"
  defp owner_label({:player, guid}), do: "player #{guid}"

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

  defp show_transport(%{character: %Character{} = character} = state) do
    case Transports.target(character) do
      nil -> system_message(state, "No active transport found on this map.")
      transport -> system_message(state, transport_label(transport))
    end
  end

  defp list_transports(%{character: %Character{internal: %{world: world}}} = state) do
    case Transports.on_world(world) do
      [] ->
        system_message(state, "No active transports found on this map.")

      transports ->
        transports
        |> Enum.reduce(system_message(state, "Active transports on #{world_label(world)}:"), fn transport, acc ->
          system_message(acc, transport_label(transport))
        end)
    end
  end

  defp advance_transport(%{character: %Character{} = character} = state, seconds, entry) do
    with {:ok, seconds} <- parse_positive_integer(seconds),
         {:ok, entry} <- parse_optional_positive_integer(entry),
         transport when not is_nil(transport) <- Transports.target(character, entry),
         {:ok, advanced} <- Transports.advance(transport.guid, seconds * 1_000) do
      state
      |> system_message("Advanced transport #{advanced.entry} by #{seconds}s.")
      |> system_message(transport_label(advanced))
    else
      nil -> system_message(state, "No matching active transport found.")
      {:error, :not_found} -> system_message(state, "Transport process is not active.")
      _ -> transport_usage(state)
    end
  end

  defp transport_usage(state) do
    system_message(state, "Invalid command. Use: .debug transport [list|advance <seconds> [entry]]")
  end

  defp transport_label(transport) do
    {x, y, z, _orientation} = transport.position
    motion = if transport.moving?, do: "moving", else: "stopped"

    "#{transport.name} entry #{transport.entry}, guid #{transport.guid}, #{world_label(transport.world)}, " <>
      "#{transport.progress_ms}ms/#{transport.period_ms}ms, #{motion}, passengers #{transport.passenger_count}, " <>
      "position #{format_coordinate(x)} #{format_coordinate(y)} #{format_coordinate(z)}"
  end

  defp format_coordinate(value), do: value |> Float.round(2) |> Float.to_string()

  defp parse_optional_positive_integer(nil), do: {:ok, nil}
  defp parse_optional_positive_integer(value), do: parse_positive_integer(value)

  defp modify_speed(state, rate) do
    case Float.parse(rate) do
      {rate, _} when rate >= @speed_min and rate <= @speed_max ->
        state
        |> apply_speed_rate(rate, resolve_speed_target(state))
        |> system_message("Speed set to #{rate}")

      _ ->
        state
        |> system_message("Invalid speed. Use: .modify speed <rate 0.1 - 10.0>")
    end
  end

  defp apply_speed_rate(state, rate, {target, _guid}) when is_pid(target) do
    character = MovementStats.set_run_speed_rate(state.character, rate)
    character = EventSink.emit(character, [Effects.movement_speed_changed(character.movement_block.run_speed)])
    put_character(state, character)
  end

  defp apply_speed_rate(state, rate, {target_guid, _guid}) do
    Entity.set_speed(target_guid, rate)
    state
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

  defp modify_hp(%{character: %Character{unit: %Unit{} = unit} = character} = state, value) do
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

  defp modify_rage(%{character: %Character{unit: %Unit{} = unit} = character} = state, value) do
    case parse_positive_integer(value) do
      {:ok, rage} ->
        rage = (rage * 10) |> min(unit.max_power2 || 0)
        character = %{character | unit: %{unit | power2: rage}}

        state
        |> put_character(character)
        |> system_message("Rage set to #{div(rage, 10)}.")

      _ ->
        system_message(state, "Invalid command. Use: .modify rage <value>")
    end
  end

  defp modify_money(%{character: %Character{player: player} = character} = state, value) do
    case Integer.parse(value) do
      {amount, ""} ->
        coinage = ((player.coinage || 0) + amount) |> max(0) |> min(@max_coinage)
        character = %{character | player: %{player | coinage: coinage}}

        state
        |> put_character(character)
        |> system_message("Money set to #{format_money(coinage)}.")

      _ ->
        system_message(state, "Invalid command. Use: .modify money <copper>")
    end
  end

  defp format_money(copper) do
    "#{div(copper, 10_000)}g #{div(rem(copper, 10_000), 100)}s #{rem(copper, 100)}c"
  end

  defp set_level(%{character: %Character{}} = state, level) do
    case parse_positive_integer(level) do
      {:ok, level} ->
        level = min(level, Stats.max_level())

        case set_character_level(state.character, level) do
          {:ok, character, level_up} ->
            state = Talents.reset_if_overbudget(%{state | character: character}, level)

            state
            |> maybe_send_level_up(level_up)
            |> put_character(state.character)
            |> system_message("Level set to #{state.character.unit.level}.")

          _ ->
            system_message(state, "Invalid level.")
        end

      _ ->
        system_message(state, "Invalid level.")
    end
  end

  defp levelup(%{character: %Character{unit: %{level: level}}} = state, levels) do
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

  defp learn_spell(state, spell_id) do
    case parse_positive_integer(spell_id) do
      {:ok, spell_id} -> learn_spells(state, [spell_id], "Already know spell #{spell_id}.")
      :error -> system_message(state, "Invalid spell id.")
    end
  end

  defp set_character_level(%Character{} = character, level) do
    level = min(level, Stats.max_level())
    old_stats = Stats.from_character(character)

    case Stats.get(character.unit.race, character.unit.class, level) do
      {:ok, new_stats} ->
        character =
          character
          |> Stats.apply(new_stats)
          |> Character.sync_equipment_stats()
          |> Character.restore_health_and_mana()
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

  defp add_rested(%{character: %Character{} = character} = state, amount) do
    case parse_positive_integer(amount) do
      {:ok, amount} ->
        character = Rest.set_bonus(character, (character.internal.rest_bonus || 0.0) + amount)

        state
        |> put_character(character)
        |> system_message("Rested bonus set to #{character.player.rest_state_experience}.")

      :error ->
        system_message(state, "Invalid amount.")
    end
  end

  defp put_player_xp(%Character{player: player} = character, xp) do
    %{character | player: %{player | xp: xp}}
  end

  defp put_character(state, %Character{} = character) do
    CharacterStore.put(character)
    PlayerServer.maybe_broadcast_update(%{state | character: Core.mark_broadcast_update(character)})
  end

  defp max_skills(%{character: %Character{unit: unit, player: player, internal: internal} = character} = state) do
    derived = SkillLoader.initial_skills(internal.spells, unit.race, unit.class, unit.level)

    skills =
      derived
      |> Map.merge(player.skills || %{})
      |> Skills.max_out()

    character = %{character | player: %{player | skills: skills}}

    state
    |> put_character(character)
    |> system_message("Skills maxed for level #{unit.level}.")
  end

  defp max_professions(%{character: %Character{player: player} = character} = state) do
    character = %{character | player: %{player | skills: Skills.max_professions(player.skills || %{})}}

    state
    |> put_character(character)
    |> system_message("Known professions set to 300/300.")
  end

  defp maybe_send_level_up(state, nil), do: state

  defp maybe_send_level_up(state, level_up) when is_map(level_up) do
    Network.send_packet(struct(Message.SmsgLevelupInfo, level_up))
    state
  end

  defp learn_spells(%{character: %Character{} = character} = state, spell_ids, known_message) do
    case Spells.learn(character, spell_ids) do
      :already_known ->
        system_message(state, known_message)

      {:ok, character, events} ->
        spellbook = character.internal.spellbook

        names =
          events
          |> Enum.flat_map(fn
            {:learned, id} -> [spell_name(spellbook, id)]
            {:superseded, _old_id, id} -> [spell_name(spellbook, id)]
            {:removed, _id} -> []
          end)
          |> Enum.join(", ")

        state
        |> Map.put(:character, character)
        |> spell_learning_message(names)
    end
  end

  defp spell_learning_message(state, ""), do: system_message(state, "Repaired duplicate spell ranks.")
  defp spell_learning_message(state, names), do: system_message(state, "Learned: #{names}")

  defp spell_name(spellbook, spell_id) do
    case Map.get(spellbook, spell_id) do
      %{name: name} -> name
      _ -> "spell #{spell_id}"
    end
  end

  defp debug_spell_ids(%{character: %Character{internal: internal, unit: %{class: class, level: level}}}) do
    ClassSpell.trainable_spell_ids(class, level, internal.spells || [])
  end

  defp debug_spell_ids(_state), do: []

  defp next_event_message(nil), do: "No more scheduled event changes."

  defp next_event_message(%{at: at, starts: starts, stops: stops}) do
    changes =
      [event_change("starts", starts), event_change("stops", stops)]
      |> Enum.reject(&is_nil/1)
      |> Enum.join("; ")

    "Next event change at #{Calendar.strftime(at, "%Y-%m-%d %H:%M:%S UTC")}: #{changes}"
  end

  defp event_change(_action, []), do: nil
  defp event_change(action, entries), do: "#{action} #{event_labels(entries)}"

  defp event_labels([]), do: "none"

  defp event_labels(entries) do
    Enum.map_join(entries, ", ", fn entry -> "#{entry.id}: #{entry.description}" end)
  end

  defp add_random_equipment(%{character: %Character{unit: unit} = character} = state) do
    existing_item_guids = owned_item_guids(character)
    prof = Proficiency.from_character(character)

    item_ids =
      unit.race
      |> ItemLoader.random_equipment(unit.class, unit.level, prof)
      |> Map.values()
      |> Enum.flat_map(fn
        %ItemTemplate{entry: entry} -> [entry]
        _ -> []
      end)

    character =
      character
      |> Characters.clear_equipment()
      |> Characters.assign_items(item_ids)
      |> Character.restore_health_and_mana()

    character
    |> new_owned_items(existing_item_guids)
    |> Enum.each(fn item ->
      item
      |> UpdateObject.from_item()
      |> Network.send_packet()
    end)

    state
    |> put_character(character)
    |> system_message("Random equipment added.")
  end

  defp owned_item_guids(%Character{player: player}) do
    player
    |> Inventory.owned_items(&ItemStore.get/1)
    |> MapSet.new(& &1.object.guid)
  end

  defp new_owned_items(%Character{player: player}, existing_item_guids) do
    player
    |> Inventory.owned_items(&ItemStore.get/1)
    |> Enum.reject(fn item -> MapSet.member?(existing_item_guids, item.object.guid) end)
  end

  defp parse_positive_integer(value) do
    case Integer.parse(value) do
      {value, ""} when value > 0 -> {:ok, value}
      _ -> :error
    end
  end

  defp system_message(state, message) do
    Network.send_packet(Message.SmsgMessagechat.system(message, state.guid))
    state
  end
end
