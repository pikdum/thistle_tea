defmodule ThistleTea.Game.Core.Battleground.AlteracValley.Ground do
  @moduledoc "Mine supply donations, assault orders, and one ground deployment per quartermaster life."

  alias ThistleTea.Game.Core.AI.CreatureScript.AlteracValleyGround
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Battleground.AlteracValley
  alias ThistleTea.Game.Core.Battleground.AlteracValley.Armor
  alias ThistleTea.Game.Core.Battleground.Effects
  alias ThistleTea.Game.Core.Battleground.Player
  alias ThistleTea.Game.Core.Battleground.Result

  defstruct [:commander_guid, irondeep: 0, coldtooth: 0, phase: :ready, quartermaster_alive?: true]

  @quartermasters %{12_096 => :alliance, 12_097 => :horde}
  @commanders %{13_446 => :alliance, 13_449 => :horde}
  @supplies %{
    5_892 => {:alliance, :irondeep, 2},
    6_982 => {:alliance, :coldtooth, 3},
    5_893 => {:horde, :coldtooth, 2},
    6_985 => {:horde, :irondeep, 3}
  }
  @orders %{6_846 => {:alliance, 13_446}, 6_901 => {:horde, 13_449}}

  def all, do: %{alliance: %__MODULE__{}, horde: %__MODULE__{}}
  def quartermaster_team(entry), do: Map.get(@quartermasters, entry)
  def order_item(12_096), do: 17_353
  def order_item(12_097), do: 17_442
  def order_item(_entry), do: nil
  def broadcast_text_ids, do: [8_907, 8_913, 9_050, 9_128]

  def contribute(%AlteracValley{phase: :active} = match, guid, quest_id) do
    case Map.get(match.players, guid) do
      %Player{status: :inside, team: team} ->
        case {Map.get(@supplies, quest_id), Map.get(@orders, quest_id)} do
          {{^team, resource, reputation}, _order} -> donate(match, team, resource, reputation)
          {_supply, {^team, commander}} -> depart(match, team, commander)
          _other -> %Result{match: match}
        end

      _ineligible ->
        %Result{match: match}
    end
  end

  def contribute(%AlteracValley{} = match, _guid, _quest_id), do: %Result{match: match}

  def gossip(match, guid, entry, standing, view \\ :root)

  def gossip(%AlteracValley{phase: :active} = match, guid, entry, standing, view) do
    with %Player{status: :inside, team: team} <- Map.get(match.players, guid),
         ^team <- quartermaster_team(entry) do
      menu(Map.fetch!(match.ground, team), team, standing, view)
    else
      _ineligible -> nil
    end
  end

  def gossip(%AlteracValley{}, _guid, _entry, _standing, _view), do: nil

  def take_orders(%AlteracValley{} = match, guid, entry, standing) do
    menu = gossip(match, guid, entry, standing)

    if menu && Enum.any?(menu.options, &(&1.action == :take_ground_orders)) do
      team = quartermaster_team(entry)
      previous = Map.fetch!(match.ground, team)
      ground = %{previous | irondeep: 0, coldtooth: 0, phase: :assembled}
      effects = if previous.phase == :ready, do: [assembly(match, entry, team)], else: []
      result = %Result{match: %{match | ground: Map.put(match.ground, team, ground)}, effects: effects}
      {:ok, order_item(entry), result}
    else
      {:error, :unavailable, %Result{match: match}}
    end
  end

  def interact(match, guid, entry, :ground_status, standing) do
    case gossip(match, guid, entry, standing, :status) do
      nil -> {:unhandled, %Result{match: match}}
      menu -> {{:menu, menu}, %Result{match: match}}
    end
  end

  def interact(match, _guid, _entry, _action, _standing), do: {:unhandled, %Result{match: match}}

  def creature_event(match, entry, event, guid \\ nil)

  def creature_event(%AlteracValley{phase: :active} = match, entry, event, guid) do
    case {quartermaster_team(entry), Map.get(@commanders, entry), event} do
      {team, _commander, 0} when not is_nil(team) -> quartermaster_spawned(match, team)
      {team, _commander, 1} when not is_nil(team) -> quartermaster_died(match, team)
      {_quartermaster, team, 2} when not is_nil(team) -> commander_died(match, team, guid)
      {_quartermaster, team, 3} when not is_nil(team) -> commander_spawned(match, team, guid)
      _other -> %Result{match: match}
    end
  end

  def creature_event(%AlteracValley{} = match, _entry, _event, _guid), do: %Result{match: match}

  defp assembly(match, entry, team) do
    %Effects.RunCreatureScript{
      creature_entry: entry,
      steps: AlteracValleyGround.assembly(team, Armor.tier(match, team))
    }
  end

  defp donate(match, team, resource, reputation) do
    ground = add(Map.fetch!(match.ground, team), resource)

    reward = %Effects.RewardReputation{
      team: team,
      faction_id: if(team == :alliance, do: 730, else: 729),
      amount: reputation
    }

    %Result{match: %{match | ground: Map.put(match.ground, team, ground)}, effects: [reward]}
  end

  defp add(%__MODULE__{} = ground, :irondeep), do: %{ground | irondeep: ground.irondeep + 10}
  defp add(%__MODULE__{} = ground, :coldtooth), do: %{ground | coldtooth: ground.coldtooth + 10}

  defp depart(match, team, commander) do
    case Map.fetch!(match.ground, team) do
      %__MODULE__{phase: :assembled, commander_guid: guid} ->
        result = change_phase(match, team, :marching)

        effect = %Effects.RunCreatureScript{
          creature_entry: commander,
          creature_guid: guid,
          steps: [%ScriptStep{command: :send_script_event, datalong: 1}]
        }

        %{result | effects: [effect]}

      _unavailable ->
        %Result{match: match}
    end
  end

  defp change_phase(match, team, phase) do
    ground = %{Map.fetch!(match.ground, team) | phase: phase}
    %Result{match: %{match | ground: Map.put(match.ground, team, ground)}}
  end

  defp quartermaster_spawned(match, team) do
    ground = %{Map.fetch!(match.ground, team) | phase: :ready, quartermaster_alive?: true, commander_guid: nil}
    put_ground(match, team, ground)
  end

  defp quartermaster_died(match, team) do
    put_ground(match, team, %{Map.fetch!(match.ground, team) | quartermaster_alive?: false})
  end

  defp commander_spawned(match, team, guid) do
    case Map.fetch!(match.ground, team) do
      %__MODULE__{phase: :assembled, commander_guid: nil} = ground ->
        put_ground(match, team, %{ground | commander_guid: guid})

      _other ->
        %Result{match: match}
    end
  end

  defp commander_died(match, team, guid) do
    case Map.fetch!(match.ground, team) do
      %__MODULE__{commander_guid: ^guid, phase: phase} when phase in [:assembled, :marching] ->
        change_phase(match, team, :defeated)

      _other ->
        %Result{match: match}
    end
  end

  defp put_ground(match, team, ground), do: %Result{match: %{match | ground: Map.put(match.ground, team, ground)}}

  defp menu(%__MODULE__{} = ground, _team, _standing, :status), do: %{text_id: status_text(ground), options: []}

  defp menu(%__MODULE__{} = ground, team, standing, :root) do
    status = %{id: 0, text_id: 9_128, action: :ground_status}
    orders = %{id: 1, text_id: 9_050, action: :take_ground_orders}
    options = if ready?(ground, team, standing), do: [status, orders], else: [status]
    %{text_id: 6_255, options: options, vendor?: true}
  end

  defp menu(%__MODULE__{}, _team, _standing, _view), do: nil

  defp ready?(
         %__MODULE__{phase: phase, quartermaster_alive?: true, irondeep: irondeep, coldtooth: coldtooth},
         team,
         standing
       )
       when phase in [:ready, :assembled] and is_integer(standing) and standing >= 9_000 do
    {iron_goal, cold_goal} = if team == :alliance, do: {280, 70}, else: {70, 280}
    irondeep >= iron_goal or coldtooth >= cold_goal
  end

  defp ready?(%__MODULE__{}, _team, _standing), do: false
  defp status_text(%__MODULE__{irondeep: iron, coldtooth: cold}) when iron + cold > 230, do: 6_731
  defp status_text(%__MODULE__{irondeep: iron, coldtooth: cold}) when iron + cold > 140, do: 6_732
  defp status_text(%__MODULE__{}), do: 6_733
end
