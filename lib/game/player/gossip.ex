defmodule ThistleTea.Game.Player.Gossip do
  @moduledoc """
  Player boundary for conditioned gossip menus and actions.
  """

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Quest
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.Script
  alias ThistleTea.Game.Entity.Logic.Condition.Subject
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.GameObjectInteraction
  alias ThistleTea.Game.Entity.Server.Player, as: PlayerServer
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.CmsgTrainerList
  alias ThistleTea.Game.Network.Message.SmsgGossipMessage.GossipItem
  alias ThistleTea.Game.Network.Message.SmsgGossipMessage.QuestItem
  alias ThistleTea.Game.Player.Auction
  alias ThistleTea.Game.Player.Bank
  alias ThistleTea.Game.Player.Battlegrounds
  alias ThistleTea.Game.Player.ConditionContext
  alias ThistleTea.Game.Player.GossipCondition
  alias ThistleTea.Game.Player.HomeBind
  alias ThistleTea.Game.Player.Petitions
  alias ThistleTea.Game.Player.PetStable
  alias ThistleTea.Game.Player.PetUntraining
  alias ThistleTea.Game.Player.QuestGiver
  alias ThistleTea.Game.Player.Quests
  alias ThistleTea.Game.Player.Reputation
  alias ThistleTea.Game.Player.TalentReset
  alias ThistleTea.Game.Player.Taxi
  alias ThistleTea.Game.Player.Vendor
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Loader.GameObjectTemplate, as: GameObjectTemplateLoader
  alias ThistleTea.Game.World.Loader.Gossip, as: GossipLoader
  alias ThistleTea.Game.World.Loader.Gossip.Menu
  alias ThistleTea.Game.World.Loader.Gossip.Option
  alias ThistleTea.Game.World.Loader.Gossip.Text
  alias ThistleTea.Game.World.Metadata

  @default_gossip_text_id 68

  def hello(%{character: %Character{} = character} = state, guid) do
    if Reputation.can_interact?(character, guid) do
      quests = quest_items(guid, character)

      case GossipLoader.menu_for_creature(Guid.entry(guid)) do
        %Menu{} = menu -> send_menu(guid, menu, quests, state)
        nil when quests != [] -> send_menu(guid, %Menu{text_id: @default_gossip_text_id, options: []}, quests, state)
        nil -> Vendor.list(state, guid)
      end
    else
      state
    end
  end

  def hello(state, _guid), do: state

  def hello_game_object(%{character: %Character{} = character} = state, guid) do
    with true <- QuestGiver.interactable?(character, guid),
         template = GameObjectTemplateLoader.cached(Guid.entry(guid)),
         {:ok, character} <-
           GameObjectInteraction.prepare_questgiver_use(character, template, Metadata.get(guid)[:go_flags], Time.now()) do
      state = put_object_user(state, character)
      menu_id = Enum.at(template.data, 3, 0)

      case GossipLoader.get_menu(menu_id) do
        %Menu{} = menu when menu_id > 0 ->
          state = Quests.credit_entity_interaction(state, guid)
          send_menu(guid, menu, quest_items(guid, state.character), state)

        _missing ->
          Quests.hello(state, guid)
      end
    else
      _invalid -> state
    end
  end

  defp put_object_user(%{character: character} = state, character), do: state

  defp put_object_user(state, character) do
    character = character |> EventSink.emit_pending() |> CharacterStore.put()
    PlayerServer.maybe_broadcast_update(%{state | character: character})
  end

  def select(%{character: %Character{} = character, gossip_menu_guid: guid} = state, guid, gossip_list_id) do
    option_ids = option_ids()

    option =
      state
      |> Map.get(:gossip_menu_options, [])
      |> Enum.find(fn %Option{id: id} -> id == gossip_list_id end)

    context = condition_context(character, guid, option_conditions(option))

    if source_allowed?(character, guid) and option_allowed?(context, option, :deny_unknown) do
      dispatch(state, character, guid, option, option_ids)
    else
      state
    end
  end

  def select(state, _guid, _gossip_list_id), do: state

  def quest_items(npc_guid, character) do
    npc_guid
    |> Quests.quest_menu(character)
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

    put_menu(state, npc_guid, options)
  end

  defp put_menu(%State{} = state, guid, options), do: %{state | gossip_menu_guid: guid, gossip_menu_options: options}
  defp put_menu(state, guid, options), do: Map.merge(state, %{gossip_menu_guid: guid, gossip_menu_options: options})

  defp source_allowed?(character, guid) do
    Guid.type_id(guid) != :game_object or QuestGiver.interactable?(character, guid)
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

  defp dispatch(
         state,
         character,
         guid,
         %Option{option_id: option_id, action_menu_id: action_menu_id, action_steps: steps},
         %{gossip: option_id}
       ) do
    state = dispatch_gossip_menu(state, character, guid, action_menu_id)

    if steps != [] do
      if Guid.type_id(guid) == :game_object do
        Entity.start_script(character.object.guid, steps, guid)
      else
        Entity.start_script(guid, steps, character.object.guid)
      end
    end

    state
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

  defp dispatch(state, _character, guid, %Option{option_id: option_id}, %{petitioner: option_id}),
    do: Petitions.show_list(state, guid)

  defp dispatch(state, _character, guid, %Option{option_id: option_id}, %{banker: option_id}),
    do: Bank.activate(state, guid)

  defp dispatch(state, _character, guid, %Option{option_id: option_id}, %{stable: option_id}),
    do: PetStable.list(state, guid)

  defp dispatch(state, _character, guid, %Option{option_id: option_id}, %{pet_untrain: option_id}),
    do: PetUntraining.confirm(state, guid)

  defp dispatch(state, _character, guid, %Option{option_id: option_id}, %{talent_reset: option_id}),
    do: TalentReset.confirm(state, guid)

  defp dispatch(state, _character, guid, %Option{option_id: option_id}, %{innkeeper: option_id}),
    do: HomeBind.confirm(state, guid)

  defp dispatch(state, character, guid, %Option{option_id: option_id}, %{spirit_healer: option_id}) do
    if not Death.alive?(character), do: Network.send_packet(%Message.SmsgSpiritHealerConfirm{guid: guid})
    state
  end

  defp dispatch(state, _character, guid, %Option{option_id: option_id}, %{battlefield: option_id}),
    do: Battlegrounds.battlemaster_hello(state, guid)

  defp dispatch(state, _character, guid, %Option{option_id: option_id}, %{auctioneer: option_id}),
    do: Auction.hello(state, guid)

  defp dispatch(state, character, guid, %Option{action_menu_id: action_menu_id}, _option_ids) do
    case GossipLoader.get_menu(action_menu_id) do
      %Menu{} = menu -> send_menu(guid, menu, submenu_quests(guid, action_menu_id, character), state)
      nil -> state
    end
  end

  defp dispatch_gossip_menu(state, character, guid, action_menu_id) when action_menu_id > 0 do
    case GossipLoader.get_menu(action_menu_id) do
      %Menu{} = menu -> send_menu(guid, menu, quest_items(guid, character), state)
      nil -> state
    end
  end

  defp dispatch_gossip_menu(state, _character, _guid, action_menu_id) when action_menu_id < 0 do
    Network.send_packet(%Message.SmsgGossipComplete{})
    %{state | gossip_menu_options: []}
  end

  defp dispatch_gossip_menu(state, _character, _guid, _action_menu_id), do: state

  defp submenu_quests(guid, menu_id, character) do
    if Guid.type_id(guid) == :game_object do
      template = GameObjectTemplateLoader.cached(Guid.entry(guid))
      if template && Enum.at(template.data, 3, 0) == menu_id, do: quest_items(guid, character), else: []
    else
      quest_items(guid, character)
    end
  end

  defp visible_options(options, npc_guid, %Character{unit: unit} = character, context) do
    trainer = GossipLoader.option_trainer()
    spirit_healer = GossipLoader.option_spirit_healer()
    stable = GossipLoader.option_stable()
    pet_untrain = GossipLoader.option_pet_untrain()
    talent_reset = GossipLoader.option_talent_reset()

    Enum.filter(options, fn option ->
      npc_flag_allowed?(option, npc_guid) and option_allowed?(context, option, :deny_unknown) and
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

          ^stable ->
            unit.class == 3

          ^pet_untrain ->
            PetUntraining.available?(character, npc_guid)

          ^talent_reset ->
            TalentReset.available?(character, npc_guid)

          _option_id ->
            true
        end
    end)
  end

  defp npc_flag_allowed?(%Option{} = option, guid) do
    if Guid.type_id(guid) == :game_object,
      do: option.option_id == GossipLoader.option_gossip(),
      else: creature_flag_allowed?(option, guid)
  end

  defp creature_flag_allowed?(%Option{npc_flag: npc_flag}, _npc_guid) when npc_flag in [nil, 0], do: true

  defp creature_flag_allowed?(%Option{npc_flag: npc_flag}, npc_guid) do
    GossipLoader.npc_flags(Guid.entry(npc_guid))
    |> Bitwise.band(npc_flag)
    |> Kernel.!=(0)
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
      gossip: GossipLoader.option_gossip(),
      vendor: GossipLoader.option_vendor(),
      taxi: GossipLoader.option_taxi(),
      trainer: GossipLoader.option_trainer(),
      spirit_healer: GossipLoader.option_spirit_healer(),
      innkeeper: GossipLoader.option_innkeeper(),
      banker: GossipLoader.option_banker(),
      petitioner: GossipLoader.option_petitioner(),
      auctioneer: GossipLoader.option_auctioneer(),
      stable: GossipLoader.option_stable(),
      battlefield: GossipLoader.option_battlefield(),
      pet_untrain: GossipLoader.option_pet_untrain(),
      talent_reset: GossipLoader.option_talent_reset()
    }
  end
end
