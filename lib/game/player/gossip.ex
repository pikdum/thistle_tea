defmodule ThistleTea.Game.Player.Gossip do
  @moduledoc """
  Player boundary for conditioned gossip menus and actions.
  """

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Quest
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.Script
  alias ThistleTea.Game.Entity.Logic.Condition.Subject
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.QuestDialogStatus
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.CmsgTrainerList
  alias ThistleTea.Game.Network.Message.SmsgGossipMessage.GossipItem
  alias ThistleTea.Game.Network.Message.SmsgGossipMessage.QuestItem
  alias ThistleTea.Game.Player.Bank
  alias ThistleTea.Game.Player.ConditionContext
  alias ThistleTea.Game.Player.GossipCondition
  alias ThistleTea.Game.Player.Quests
  alias ThistleTea.Game.Player.Reputation
  alias ThistleTea.Game.Player.Taxi
  alias ThistleTea.Game.Player.Vendor
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.Loader.Gossip, as: GossipLoader
  alias ThistleTea.Game.World.Loader.Gossip.Menu
  alias ThistleTea.Game.World.Loader.Gossip.Option
  alias ThistleTea.Game.World.Loader.Gossip.Text

  @default_gossip_text_id 68

  def hello(%{character: %Character{} = character} = state, guid) do
    if Reputation.can_interact?(character, guid) do
      quests = quest_items(guid, character)

      case GossipLoader.menu_for_creature(Guid.entry(guid)) do
        %Menu{} = menu -> send_menu(guid, menu, quests, state)
        nil when quests != [] -> send_menu(guid, %Menu{text_id: @default_gossip_text_id, options: []}, quests, state)
        nil -> state
      end
    else
      state
    end
  end

  def hello(state, _guid), do: state

  def select(%{character: %Character{} = character} = state, guid, gossip_list_id) do
    option_ids = option_ids()

    option =
      state
      |> Map.get(:gossip_menu_options, [])
      |> Enum.find(fn %Option{id: id} -> id == gossip_list_id end)

    context = condition_context(character, guid, option_conditions(option))

    if option_allowed?(context, option, :deny_unknown) do
      dispatch(state, character, guid, option, option_ids)
    else
      state
    end
  end

  def select(state, _guid, _gossip_list_id), do: state

  def quest_items(npc_guid, character) do
    {giver_quests, ender_quests} = Quests.npc_quests(npc_guid)

    giver_quests
    |> QuestDialogStatus.menu(ender_quests, Quests.ctx(character))
    |> Enum.map(fn {%Quest{} = quest, icon} ->
      %QuestItem{quest_id: quest.id, quest_icon: icon, level: quest.level, title: quest.title}
    end)
  end

  def send_menu(npc_guid, %Menu{} = menu, quests, %{character: %Character{} = character} = state) do
    context = condition_context(character, npc_guid, menu_conditions(menu))
    options = visible_options(menu.options, npc_guid, character, context)

    gossips =
      Enum.map(options, fn option ->
        %GossipItem{id: option.id, item_icon: option.icon, coded: option.coded, message: option.text}
      end)

    Network.send_packet(%Message.SmsgGossipMessage{
      guid: npc_guid,
      title_text_id: context_title_text_id(menu, context),
      gossips: gossips,
      quests: quests
    })

    %{state | gossip_menu_options: options}
  end

  def title_text_id(%Menu{} = menu, %Character{} = character), do: title_text_id(menu, character, 0)

  def title_text_id(%Menu{} = menu, %Character{} = character, npc_guid) do
    context = condition_context(character, npc_guid, Enum.map(menu.texts, & &1.condition))
    context_title_text_id(menu, context)
  end

  defp context_title_text_id(%Menu{texts: texts}, context) when texts != [] do
    texts
    |> Enum.filter(fn
      %Text{condition_id: 0} -> true
      %Text{condition: condition} -> GossipCondition.allows?(context, condition, :deny_unknown)
    end)
    |> Enum.max_by(& &1.condition_id, fn -> %Text{text_id: @default_gossip_text_id} end)
    |> then(& &1.text_id)
  end

  defp context_title_text_id(%Menu{text_id: text_id}, _context) when is_integer(text_id), do: text_id
  defp context_title_text_id(%Menu{}, _context), do: @default_gossip_text_id

  def run_taxi_script(%{character: %Character{} = character} = state, steps) when is_list(steps) do
    Network.send_packet(%Message.SmsgGossipComplete{})
    {character, _blackboard} = Script.run(character, Blackboard.new(), steps, character.object.guid, Time.now())
    character = EventSink.emit_pending(character)
    %{state | character: character, gossip_menu_options: []}
  end

  defp dispatch(state, _character, _guid, %Option{taxi_path_steps: [_ | _] = steps}, _option_ids) do
    run_taxi_script(state, steps)
  end

  defp dispatch(state, character, guid, %Option{option_id: option_id}, %{vendor: option_id}) do
    Network.send_packet(%Message.SmsgListInventory{
      vendor_guid: guid,
      items: Vendor.visible_items(character, guid)
    })

    state
  end

  defp dispatch(state, _character, guid, %Option{option_id: option_id}, %{taxi: option_id}), do: Taxi.query(state, guid)

  defp dispatch(state, _character, guid, %Option{option_id: option_id}, %{trainer: option_id}),
    do: CmsgTrainerList.send_list(state, guid)

  defp dispatch(state, _character, guid, %Option{option_id: option_id}, %{banker: option_id}),
    do: Bank.activate(state, guid)

  defp dispatch(state, character, guid, %Option{option_id: option_id}, %{spirit_healer: option_id}) do
    if not Death.alive?(character), do: Network.send_packet(%Message.SmsgSpiritHealerConfirm{guid: guid})
    state
  end

  defp dispatch(state, character, guid, %Option{action_menu_id: action_menu_id}, _option_ids) do
    case GossipLoader.get_menu(action_menu_id) do
      %Menu{} = menu -> send_menu(guid, menu, quest_items(guid, character), state)
      nil -> state
    end
  end

  defp visible_options(options, npc_guid, %Character{unit: unit} = character, context) do
    trainer = GossipLoader.option_trainer()
    spirit_healer = GossipLoader.option_spirit_healer()

    Enum.filter(options, fn option ->
      option_allowed?(context, option, :deny_unknown) and
        case option.option_id do
          ^trainer ->
            GossipLoader.trainer_of?(
              Guid.entry(npc_guid),
              unit.class,
              unit.race,
              Reputation.exalted_with?(character, npc_guid)
            )

          ^spirit_healer ->
            not Death.alive?(character)

          _option_id ->
            true
        end
    end)
  end

  defp option_allowed?(_context, nil, _policy), do: false

  defp option_allowed?(context, %Option{condition: condition}, policy),
    do: GossipCondition.allows?(context, condition, policy)

  defp condition_context(character, npc_guid, conditions) do
    source = %Subject{guid: npc_guid, kind: :creature, entry: Guid.entry(npc_guid)}
    ConditionContext.build(character, conditions, source: source)
  end

  defp menu_conditions(%Menu{texts: texts, options: options}) do
    Enum.map(texts, & &1.condition) ++ Enum.map(options, & &1.condition)
  end

  defp option_conditions(nil), do: []
  defp option_conditions(%Option{condition: condition}), do: [condition]

  defp option_ids do
    %{
      vendor: GossipLoader.option_vendor(),
      taxi: GossipLoader.option_taxi(),
      trainer: GossipLoader.option_trainer(),
      spirit_healer: GossipLoader.option_spirit_healer(),
      banker: GossipLoader.option_banker()
    }
  end
end
