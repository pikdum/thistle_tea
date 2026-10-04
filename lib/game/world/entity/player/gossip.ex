defmodule ThistleTea.Game.World.Entity.Player.Gossip do
  @moduledoc """
  Player boundary for conditioned gossip menus and actions.
  """

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.Script
  alias ThistleTea.Game.Core.Condition.Subject
  alias ThistleTea.Game.Core.Death
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.GameObjectTemplate
  alias ThistleTea.Game.Core.GameObject.GameObjectInteraction
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Quest
  alias ThistleTea.Game.Core.Time
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.SmsgGossipMessage.GossipItem
  alias ThistleTea.Game.Network.Message.SmsgGossipMessage.QuestItem
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Entity.EventSink
  alias ThistleTea.Game.World.Entity.Player, as: PlayerServer
  alias ThistleTea.Game.World.Entity.Player.Auction
  alias ThistleTea.Game.World.Entity.Player.Bank
  alias ThistleTea.Game.World.Entity.Player.Battlegrounds
  alias ThistleTea.Game.World.Entity.Player.ConditionContext
  alias ThistleTea.Game.World.Entity.Player.GameObjects
  alias ThistleTea.Game.World.Entity.Player.GossipCondition
  alias ThistleTea.Game.World.Entity.Player.Guilds
  alias ThistleTea.Game.World.Entity.Player.HomeBind
  alias ThistleTea.Game.World.Entity.Player.Petitions
  alias ThistleTea.Game.World.Entity.Player.PetStable
  alias ThistleTea.Game.World.Entity.Player.PetUntraining
  alias ThistleTea.Game.World.Entity.Player.QuestGiver
  alias ThistleTea.Game.World.Entity.Player.Quests
  alias ThistleTea.Game.World.Entity.Player.Reputation
  alias ThistleTea.Game.World.Entity.Player.State
  alias ThistleTea.Game.World.Entity.Player.TalentReset
  alias ThistleTea.Game.World.Entity.Player.Taxi
  alias ThistleTea.Game.World.Entity.Player.Training
  alias ThistleTea.Game.World.Entity.Player.Vendor
  alias ThistleTea.Game.World.Loader.GameObjectScript, as: GameObjectScriptLoader
  alias ThistleTea.Game.World.Loader.GameObjectTemplate, as: GameObjectTemplateLoader
  alias ThistleTea.Game.World.Loader.Gossip, as: GossipLoader
  alias ThistleTea.Game.World.Loader.Gossip.Menu
  alias ThistleTea.Game.World.Loader.Gossip.Option
  alias ThistleTea.Game.World.Loader.Gossip.Poi
  alias ThistleTea.Game.World.Loader.Gossip.Text
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Outbound

  @default_gossip_text_id 68

  def default_text_id, do: @default_gossip_text_id

  def hello(%{character: %Character{} = character} = state, guid) do
    if Reputation.can_interact?(character, guid) do
      Entity.pause_for_talk(guid)
      quests = quest_items(guid, character)

      case Battlegrounds.gossip_menu(character, guid) || creature_menu(guid) do
        %Menu{} = menu -> send_menu(guid, menu, quests, state)
        nil when quests != [] -> send_menu(guid, %Menu{text_id: @default_gossip_text_id, options: []}, quests, state)
        nil -> Vendor.list(state, guid)
      end
    else
      state
    end
  end

  def hello(state, _guid), do: state

  def creature_menu(guid) do
    case Metadata.query(guid, [:gossip_menu_id]) do
      %{gossip_menu_id: menu_id} when is_integer(menu_id) -> GossipLoader.get_menu(menu_id)
      _template -> GossipLoader.menu_for_creature(World.entry(guid))
    end
  end

  def hello_game_object(%{character: %Character{} = character} = state, guid) do
    with true <- QuestGiver.interactable?(character, guid),
         template = GameObjectTemplateLoader.cached(World.entry(guid)),
         {:ok, character} <-
           GameObjectInteraction.prepare_questgiver_use(character, template, Metadata.get(guid)[:go_flags], Time.now()) do
      state = put_object_user(state, character)
      start_hello_script(guid, state.character)
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

  defp start_hello_script(guid, %Character{} = character) do
    with {_world, x, y, z} <- World.position(guid),
         [_ | _] = steps <- GameObjectScriptLoader.ported(World.entry(guid), {x, y, z, 0.0}) do
      Entity.start_script(character.object.guid, steps, guid)
    end
  end

  defp put_object_user(%{character: character} = state, character), do: state

  defp put_object_user(state, character) do
    character = character |> EventSink.emit_pending() |> CharacterStore.put()
    PlayerServer.maybe_broadcast_update(%{state | character: character})
  end

  def hello_quest_object(state, guid, menu_id) do
    case GossipLoader.get_menu(menu_id) do
      %Menu{} = menu -> send_menu(guid, menu, [], state)
      _ -> state
    end
  end

  def select(%{character: %Character{} = character, gossip_menu_guid: guid} = state, guid, gossip_list_id) do
    option_ids = option_ids()

    option =
      state
      |> Map.get(:gossip_menu_options, [])
      |> Enum.find(fn %Option{id: id} -> id == gossip_list_id end)

    context = condition_context(character, guid, option_conditions(option))

    if source_allowed?(character, guid) and option_allowed?(context, option, :deny_unknown) do
      Entity.pause_for_talk(guid)
      dispatch(state, character, guid, option, option_ids)
    else
      state
    end
  end

  def select(state, _guid, _gossip_list_id), do: state

  def quest_items(npc_guid, character) do
    if QuestGiver.offers_quests?(npc_guid) do
      npc_guid
      |> Quests.quest_menu(character)
      |> Enum.map(fn {%Quest{} = quest, icon} ->
        %QuestItem{quest_id: quest.id, quest_icon: icon, level: quest.level, title: quest.title}
      end)
    else
      []
    end
  end

  def send_menu(npc_guid, %Menu{} = menu, quests, %{character: %Character{} = character} = state) do
    context = condition_context(character, npc_guid, menu_conditions(menu))
    options = visible_options(menu.options, npc_guid, character, context)

    gossips =
      Enum.map(options, fn option ->
        %GossipItem{id: option.id, item_icon: option.icon, coded: option.coded, message: option.text}
      end)

    text = context_title_text(menu, context)

    Outbound.send_packet(%Message.SmsgGossipMessage{
      guid: npc_guid,
      title_text_id: text.text_id,
      gossips: gossips,
      quests: quests
    })

    start_text_script(text, npc_guid, character)
    put_menu(state, npc_guid, options)
  end

  defp start_text_script(%Text{script_steps: [_ | _] = steps}, npc_guid, %Character{} = character) do
    Entity.start_script(npc_guid, steps, character.object.guid)
  end

  defp start_text_script(%Text{}, _npc_guid, _character), do: :ok

  defp put_menu(%State{} = state, guid, options), do: %{state | gossip_menu_guid: guid, gossip_menu_options: options}
  defp put_menu(state, guid, options), do: Map.merge(state, %{gossip_menu_guid: guid, gossip_menu_options: options})

  defp source_allowed?(character, guid) do
    cond do
      Guid.type_id(guid) != :game_object ->
        true

      match?(%GameObjectTemplate{type: 10}, GameObjectTemplateLoader.cached(World.entry(guid))) ->
        GameObjects.interactable?(character, guid)

      true ->
        QuestGiver.interactable?(character, guid)
    end
  end

  def title_text_id(%Menu{} = menu, %Character{} = character), do: title_text_id(menu, character, 0)

  def title_text_id(%Menu{} = menu, %Character{} = character, npc_guid) do
    context = condition_context(character, npc_guid, Enum.map(menu.texts, & &1.condition))
    context_title_text(menu, context).text_id
  end

  defp context_title_text(%Menu{texts: texts}, context) when texts != [] do
    texts
    |> Enum.filter(fn
      %Text{condition_id: 0} -> true
      %Text{condition: condition} -> GossipCondition.allows?(context, condition, :deny_unknown)
    end)
    |> Enum.max_by(& &1.condition_id, fn -> %Text{text_id: @default_gossip_text_id} end)
  end

  defp context_title_text(%Menu{text_id: text_id}, _context) when is_integer(text_id), do: %Text{text_id: text_id}
  defp context_title_text(%Menu{}, _context), do: %Text{text_id: @default_gossip_text_id}

  def run_taxi_script(%{character: %Character{} = character} = state, steps) when is_list(steps) do
    Outbound.send_packet(%Message.SmsgGossipComplete{})
    {character, _blackboard} = Script.run(character, Blackboard.new(), steps, character.object.guid, Time.now())
    character = EventSink.emit_pending(character)
    %{state | character: character, gossip_menu_options: []}
  end

  defp dispatch(state, _character, _guid, %Option{taxi_path_steps: [_ | _] = steps}, _option_ids) do
    run_taxi_script(state, steps)
  end

  defp dispatch(state, _character, guid, %Option{action: {:battleground, action}}, _option_ids),
    do: Battlegrounds.select_gossip(state, guid, action)

  defp dispatch(state, character, guid, %Option{option_id: option_id, action_steps: steps} = option, %{
         gossip: option_id
       }) do
    send_poi(option)
    state = dispatch_gossip_menu(state, character, guid, option)

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
    Outbound.send_packet(%Message.SmsgListInventory{
      vendor_guid: guid,
      items: Vendor.visible_items(character, guid)
    })

    state
  end

  defp dispatch(state, _character, guid, %Option{option_id: option_id}, %{taxi: option_id}), do: Taxi.query(state, guid)

  defp dispatch(state, _character, guid, %Option{option_id: option_id}, %{trainer: option_id}),
    do: Training.send_list(state, guid)

  defp dispatch(state, _character, guid, %Option{option_id: option_id}, %{petitioner: option_id}),
    do: Petitions.show_list(state, guid)

  defp dispatch(state, _character, guid, %Option{option_id: option_id}, %{tabard_designer: option_id}),
    do: Guilds.activate_tabard(state, guid)

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
    if not Death.alive?(character), do: Outbound.send_packet(%Message.SmsgSpiritHealerConfirm{guid: guid})
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

  defp dispatch_gossip_menu(state, _character, guid, %Option{action_menu_id: {:creature_reply, _entry, _id} = menu_id}) do
    case GossipLoader.get_menu(menu_id) do
      %Menu{} = menu -> send_menu(guid, menu, [], state)
      nil -> state
    end
  end

  defp dispatch_gossip_menu(state, character, guid, %Option{action_menu_id: action_menu_id})
       when is_integer(action_menu_id) and action_menu_id > 0 do
    case GossipLoader.get_menu(action_menu_id) do
      %Menu{} = menu -> send_menu(guid, menu, quest_items(guid, character), state)
      nil -> state
    end
  end

  defp dispatch_gossip_menu(state, _character, guid, %Option{action_menu_id: action_menu_id} = option)
       when action_menu_id < 0 do
    Outbound.send_packet(%Message.SmsgGossipComplete{})
    state = %{state | gossip_menu_options: []}
    if option.talk_credit? and Guid.type_id(guid) == :unit, do: Quests.credit_talk(state, guid), else: state
  end

  defp dispatch_gossip_menu(state, _character, _guid, _option), do: state

  defp send_poi(%Option{poi: %Poi{} = poi}) do
    Outbound.send_packet(%Message.SmsgGossipPoi{
      flags: poi.flags,
      x: poi.x,
      y: poi.y,
      icon: poi.icon,
      data: poi.data,
      name: poi.name
    })
  end

  defp send_poi(_option), do: :ok

  defp submenu_quests(guid, menu_id, character) do
    if Guid.type_id(guid) == :game_object do
      template = GameObjectTemplateLoader.cached(World.entry(guid))
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
              World.entry(npc_guid),
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
    npc_guid
    |> live_npc_flags()
    |> Bitwise.band(npc_flag)
    |> Kernel.!=(0)
  end

  defp live_npc_flags(npc_guid) do
    case Metadata.get(npc_guid) do
      %{npc_flags: flags} when is_integer(flags) -> flags
      _ -> GossipLoader.npc_flags(World.entry(npc_guid))
    end
  end

  defp option_allowed?(_context, nil, _policy), do: false

  defp option_allowed?(context, %Option{condition: condition}, policy),
    do: GossipCondition.allows?(context, condition, policy)

  defp condition_context(character, npc_guid, conditions) do
    source = %Subject{guid: npc_guid, kind: :creature, entry: World.entry(npc_guid)}
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
      tabard_designer: GossipLoader.option_tabard_designer(),
      auctioneer: GossipLoader.option_auctioneer(),
      stable: GossipLoader.option_stable(),
      battlefield: GossipLoader.option_battlefield(),
      pet_untrain: GossipLoader.option_pet_untrain(),
      talent_reset: GossipLoader.option_talent_reset()
    }
  end
end
