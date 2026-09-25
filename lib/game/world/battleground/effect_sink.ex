defmodule ThistleTea.Game.World.Battleground.EffectSink do
  @moduledoc """
  Projects battleground effects into live entities, packets, and world spawns.
  """

  alias ThistleTea.Game.Battleground.Effects
  alias ThistleTea.Game.Battleground.Lifecycle
  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Data.Honor.Award
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Battleground.Buffs
  alias ThistleTea.Game.World.Battleground.Graveyard
  alias ThistleTea.Game.World.Battleground.Spawns
  alias ThistleTea.Game.World.Loader.Battleground, as: BattlegroundLoader
  alias ThistleTea.Game.World.Loader.BroadcastText, as: BroadcastTextLoader
  alias ThistleTea.Game.World.Loader.GameObjectTemplate, as: GameObjectTemplateLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpawnPool
  alias ThistleTea.Game.World.System.Honor

  @alliance_flag_aura 23_335
  @horde_flag_aura 23_333

  def emit(%{world: _world, players: _players} = match, effects, opts \\ []) when is_list(effects) do
    Enum.each(effects, fn
      %Effects.StartBuffs{positions: positions} ->
        Buffs.start(match.world, Keyword.fetch!(opts, :owner), positions)

      %Effects.StopBuffs{} ->
        Buffs.stop(match.world)

      %Effects.ScheduleTimer{key: key, delays: delays} ->
        delay = Keyword.get(opts, :choose_delay, &Enum.random/1).(delays)
        Process.send_after(Keyword.fetch!(opts, :owner), {:battleground_timer, key}, delay)

      effect ->
        emit_effect(match, effect)
    end)

    :ok
  end

  defp emit_effect(match, %Effects.OperateGates{action: action}) do
    gate_entries = MapSet.new(BattlegroundLoader.gate_entries(match.world.map_id))

    match.world
    |> World.guids()
    |> Enum.filter(&MapSet.member?(gate_entries, Guid.entry(&1)))
    |> Enum.each(&Entity.operate_game_object(&1, action))
  end

  defp emit_effect(match, %Effects.DespawnGhostGates{}) do
    Spawns.set_event(match.world, 253, nil)
  end

  defp emit_effect(match, %Effects.SetEvent{event: event, state: state}) do
    Spawns.set_event(match.world, event, state)
  end

  defp emit_effect(match, %Effects.StopEventRespawns{event: event}) do
    Spawns.stop_respawns(match.world, event)
  end

  defp emit_effect(match, %Effects.NodeAnnouncement{} = effect) do
    node = Enum.at(["Stables", "Blacksmith", "Farm", "Lumber Mill", "Gold Mine"], effect.node)
    faction = if effect.team == :alliance, do: "Alliance", else: "Horde"

    text =
      case effect.action do
        :claimed -> "$n claims the #{node}! If left unchallenged, the #{faction} will control it in 1 minute!"
        :assaulted -> "$n has assaulted the #{node}!"
        :defended -> "$n has defended the #{node}!"
        :captured -> "The #{faction} has taken the #{node}!"
      end

    packet = battleground_message(replace_actor(text, effect.actor_guid), effect.team, effect.actor_guid)
    send_to(match, :all, packet)
  end

  defp emit_effect(match, %Effects.ObjectiveAnnouncement{} = effect) do
    faction = if effect.team == :alliance, do: "Alliance", else: "Horde"

    text =
      case {effect.kind, effect.action} do
        {:tower, :captured} -> "The #{faction} has destroyed #{effect.name}!"
        {:mine, :reclaimed} -> "#{effect.name} has been reclaimed by its original inhabitants!"
        {:captain, :buff} -> "#{effect.name} rallies the #{faction} troops!"
        {_kind, :assaulted} -> "The #{faction} has assaulted #{effect.name}!"
        {_kind, :defended} -> "The #{faction} has defended #{effect.name}!"
        {_kind, :captured} -> "The #{faction} has taken #{effect.name}!"
      end

    send_to(match, :all, battleground_message(text, effect.team || :neutral, nil))
  end

  defp emit_effect(_match, %Effects.QuestKillCredit{guid: guid, entry: entry}),
    do: Entity.quest_kill_credit(guid, entry)

  defp emit_effect(match, %Effects.ArmorUpgrade{team: team, tier: tier}) do
    rank = Enum.at(["Seasoned", "Veteran", "Champion"], tier - 1)
    send_to(match, team, battleground_message("#{rank} units are entering the battle!", team, nil))
  end

  defp emit_effect(match, %Effects.TeamSpell{team: team, spell_id: spell_id}) do
    match.players
    |> Map.values()
    |> Enum.filter(&(&1.team == team and &1.status == :inside))
    |> Enum.each(&Entity.trigger_spell(&1.guid, spell_id, &1.guid, triggered: true))
  end

  defp emit_effect(match, %Effects.UpdateStatus{}) do
    now = Time.now()
    elapsed_ms = max(now - match.started_at, 0)

    packet = %Message.SmsgBattlefieldStatus{
      map: match.world.map_id,
      bracket: match.bracket,
      client_instance_id: match.client_instance_id,
      status: :in_progress,
      time_one_ms: Lifecycle.auto_leave_ms(match, now),
      time_two_ms: elapsed_ms
    }

    send_to(match, :all, packet)
  end

  defp emit_effect(_match, %Effects.HideGameObject{guid: guid}), do: Entity.hide_game_object(guid)

  defp emit_effect(match, %Effects.ShowBaseFlag{team: team}) do
    case BattlegroundLoader.base_flag_db_guid(team) do
      guid when is_integer(guid) -> SpawnPool.resume_game_object(match.world, guid)
      _missing -> :ok
    end
  end

  defp emit_effect(match, %Effects.HideBaseFlags{}) do
    match.world
    |> World.guids()
    |> Enum.filter(&(Guid.entry(&1) in [179_830, 179_831]))
    |> Enum.each(&Entity.hide_game_object/1)
  end

  defp emit_effect(match, %Effects.SpawnDroppedFlag{} = effect) do
    entry = if effect.team == :alliance, do: 179_785, else: 179_786

    case GameObjectTemplateLoader.cached(entry) do
      nil ->
        :ok

      template ->
        game_object = GameObject.build_summoned(template, match.world, effect.position)
        game_object = %{game_object | object: %{game_object.object | guid: effect.guid}}
        World.start_incarnation(game_object)
    end
  end

  defp emit_effect(_match, %Effects.DespawnGameObject{guid: guid}), do: Entity.hide_game_object(guid)

  defp emit_effect(_match, %Effects.ApplyFlagAura{guid: guid, team: team}) do
    Entity.trigger_spell(guid, flag_aura(team), guid, triggered: true)
  end

  defp emit_effect(_match, %Effects.RemoveFlagAura{guid: guid, team: team}) do
    Entity.remove_spell_auras(guid, [flag_aura(team)])
  end

  defp emit_effect(match, %Effects.UpdateWorldStates{states: states}) do
    packets = Enum.map(states, fn {state, value} -> %Message.SmsgUpdateWorldState{state: state, value: value} end)
    send_to(match, :all, packets)
  end

  defp emit_effect(match, %Effects.Announce{} = effect) do
    case BroadcastTextLoader.get(effect.broadcast_text_id) do
      %{text: text} ->
        text = replace_actor(text, effect.actor_guid)
        packet = battleground_message(text, effect.audience, effect.actor_guid)
        send_to(match, :all, packet)

      _missing ->
        :ok
    end
  end

  defp emit_effect(match, %Effects.PlaySound{sound_id: sound_id}) do
    send_to(match, :all, %Message.SmsgPlaySound{sound_id: sound_id})
  end

  defp emit_effect(match, %Effects.PlayerJoined{guid: guid}) do
    send_to(match, :all, %Message.SmsgBattlegroundPlayerJoined{guid: guid}, except: guid)
  end

  defp emit_effect(match, %Effects.PlayerLeft{guid: guid}) do
    send_to(match, :all, %Message.SmsgBattlegroundPlayerLeft{guid: guid}, except: guid)
  end

  defp emit_effect(match, %Effects.ResurrectPlayers{guids: guids}) do
    Enum.each(guids, fn guid ->
      case Map.get(match.players, guid) do
        %{team: _team} -> Entity.battleground_resurrect(guid, Graveyard.for_player(match, guid))
        _missing -> :ok
      end
    end)
  end

  defp emit_effect(match, %Effects.Scoreboard{} = effect) do
    packet = %Message.MsgPvpLogData{ended?: effect.ended?, winner: effect.winner || :none, players: effect.players}
    send_to(match, :all, packet)
  end

  defp emit_effect(match, %Effects.RewardPlayers{} = effect) do
    Enum.each(effect.players, fn %{guid: guid, team: team} ->
      spell_id = reward_spell(match, effect.winner, team)
      if is_integer(spell_id) and spell_id > 0, do: Entity.trigger_spell(guid, spell_id, guid, triggered: true)
    end)
  end

  defp emit_effect(match, %Effects.RewardReputation{} = effect) do
    match.players
    |> Map.values()
    |> Enum.filter(&(&1.status == :inside and &1.team == effect.team))
    |> Enum.each(&Entity.reward_reputation(&1.guid, effect.faction_id, effect.amount))
  end

  defp emit_effect(_match, %Effects.RewardHonor{guids: guids, amount: amount}) do
    Enum.each(guids, &Honor.award(&1, %Award{type: :bonus, points: amount}))
  end

  defp emit_effect(_match, %Effects.ExitPlayers{destinations: destinations}) do
    Enum.each(destinations, fn {guid, destination} ->
      case destination do
        {world, {x, y, z, orientation}} -> Entity.battleground_exit(guid, world, {x, y, z, orientation})
        _missing -> :ok
      end
    end)
  end

  defp flag_aura(:alliance), do: @alliance_flag_aura
  defp flag_aura(:horde), do: @horde_flag_aura

  defp send_to(match, audience, packets, opts \\ []) do
    except = Keyword.get(opts, :except)

    match.players
    |> Map.values()
    |> Enum.filter(&(&1.status == :inside and audience?(&1.team, audience) and &1.guid != except))
    |> Enum.each(&Network.send_packet(packets, &1.guid))
  end

  defp audience?(_team, :all), do: true
  defp audience?(_team, :neutral), do: true
  defp audience?(team, team), do: true
  defp audience?(_team, _audience), do: false

  defp battleground_message(text, audience, actor_guid) do
    chat_type = if audience in [:alliance, :horde], do: audience, else: :neutral

    %Message.SmsgMessagechat{
      chat_type: Message.SmsgMessagechat.chat_type(:"battleground_#{chat_type}"),
      language: 0,
      sender_guid: actor_guid || 0,
      message: text,
      channel_name: nil,
      player_rank: 0,
      tag: 0
    }
  end

  defp replace_actor(text, nil), do: text

  defp replace_actor(text, guid) do
    name =
      case Metadata.query(guid, [:name]) do
        %{name: name} when is_binary(name) -> name
        _missing -> "Unknown"
      end

    String.replace(text, "$n", name)
  end

  defp reward_spell(match, winner, :alliance) do
    if winner == :alliance, do: match.template.alliance_win_spell, else: match.template.alliance_lose_spell
  end

  defp reward_spell(match, winner, :horde) do
    if winner == :horde, do: match.template.horde_win_spell, else: match.template.horde_lose_spell
  end
end
