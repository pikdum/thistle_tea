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
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.MovementStats
  alias ThistleTea.Game.Entity.Logic.Proficiency
  alias ThistleTea.Game.Entity.Logic.QuestLog
  alias ThistleTea.Game.Entity.Logic.Rest
  alias ThistleTea.Game.Entity.Logic.Skills
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Server
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.Player.Characters
  alias ThistleTea.Game.Player.Exploration, as: PlayerExploration
  alias ThistleTea.Game.Player.Items
  alias ThistleTea.Game.Player.Quests
  alias ThistleTea.Game.Player.Spells
  alias ThistleTea.Game.Player.Stats
  alias ThistleTea.Game.Player.Talents
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.ClassSpell
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader
  alias ThistleTea.Game.World.Loader.Quest, as: QuestLoader
  alias ThistleTea.Game.World.Loader.Skill, as: SkillLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.PostOffice
  alias ThistleTea.Game.World.System.GameEvent
  alias ThistleTea.Game.World.System.Instance, as: InstanceSystem
  alias ThistleTea.Game.WorldRef

  require Logger

  @speed_min 0.1
  @speed_max 10.0
  @max_coinage 0x7FFFFFFF

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
      ".debug skills - max out known skills for your level",
      ".debug spells - learn class trainer spells up to your level",
      ".debug events - show active events and the next scheduled change",
      ".debug explore - unlock every world-map area",
      ".character level <level> - set player level",
      ".die - kill your character",
      ".go xyz <x> <y> <z> [map] - teleport",
      ".guid - show target guid",
      ".help - show help",
      ".instance info - show instance ownership and membership",
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
    system_message(state, "Teleporting to #{x}, #{y}, #{z} on map #{map}")

    GenServer.cast(self(), {:start_teleport, x, y, z, map})

    state
  end

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
    character = EventSink.emit(character, [Event.movement_speed_changed(character.movement_block.run_speed)])
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
    Server.maybe_broadcast_update(%{state | character: Core.mark_broadcast_update(character)})
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

  defp debug_spell_ids(%{character: %Character{unit: %{class: class, level: level}}}) do
    ClassSpell.trainable_spell_ids(class, level)
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
