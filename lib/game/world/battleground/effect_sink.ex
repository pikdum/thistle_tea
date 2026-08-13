defmodule ThistleTea.Game.World.Battleground.EffectSink do
  @moduledoc """
  Projects battleground effects into live entities, packets, and world spawns.
  """

  alias ThistleTea.Game.Battleground.Effects
  alias ThistleTea.Game.Battleground.WarsongGulch
  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.Battleground, as: BattlegroundLoader
  alias ThistleTea.Game.World.Loader.BroadcastText, as: BroadcastTextLoader
  alias ThistleTea.Game.World.Loader.GameObjectTemplate, as: GameObjectTemplateLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpawnPool

  @alliance_flag_aura 23_335
  @horde_flag_aura 23_333

  def emit(%WarsongGulch{} = match, effects) when is_list(effects) do
    Enum.each(effects, &emit_effect(match, &1))
    :ok
  end

  defp emit_effect(match, %Effects.OperateGates{action: action}) do
    gate_entries = MapSet.new(BattlegroundLoader.gate_entries())

    match.world
    |> World.guids()
    |> Enum.filter(&MapSet.member?(gate_entries, Guid.entry(&1)))
    |> Enum.each(&Entity.operate_game_object(&1, action))
  end

  defp emit_effect(match, %Effects.DespawnGhostGates{}) do
    Enum.each(BattlegroundLoader.ghost_gate_db_guids(), &SpawnPool.suspend_game_object(match.world, &1, nil))
  end

  defp emit_effect(match, %Effects.UpdateStatus{}) do
    elapsed_ms = max(Time.now() - match.started_at, 0)

    packet = %Message.SmsgBattlefieldStatus{
      map: match.world.map_id,
      bracket: match.bracket,
      client_instance_id: match.client_instance_id,
      status: :in_progress,
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
        %{team: team} -> Entity.battleground_resurrect(guid, graveyard(match, team))
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

  defp emit_effect(_match, %Effects.ExitPlayers{destinations: destinations}) do
    Enum.each(destinations, fn {guid, destination} ->
      case destination do
        {world, {x, y, z, orientation}} -> Entity.teleport(guid, world, {x, y, z, orientation})
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

  defp graveyard(match, :alliance), do: match.template.alliance_graveyard || match.template.alliance_start
  defp graveyard(match, :horde), do: match.template.horde_graveyard || match.template.horde_start

  defp reward_spell(match, winner, :alliance) do
    if winner == :alliance, do: match.template.alliance_win_spell, else: match.template.alliance_lose_spell
  end

  defp reward_spell(match, winner, :horde) do
    if winner == :horde, do: match.template.horde_win_spell, else: match.template.horde_lose_spell
  end
end
