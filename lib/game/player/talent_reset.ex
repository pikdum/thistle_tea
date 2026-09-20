defmodule ThistleTea.Game.Player.TalentReset.Offer do
  @moduledoc false
  @enforce_keys [:trainer_guid, :cost]
  defstruct @enforce_keys
end

defmodule ThistleTea.Game.Player.TalentReset do
  @moduledoc """
  Class-trainer talent reset confirmation, payment, and companion cleanup.
  """

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Companion, as: CompanionData
  alias ThistleTea.Game.Entity.Data.Companion.EntityRef
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.TalentReset, as: ResetPrice
  alias ThistleTea.Game.Entity.Logic.Talents, as: TalentLogic
  alias ThistleTea.Game.Entity.Server.Player.CompanionOwner
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.CompanionVisibility
  alias ThistleTea.Game.Player.Items
  alias ThistleTea.Game.Player.Reputation
  alias ThistleTea.Game.Player.TalentReset.Offer
  alias ThistleTea.Game.Player.Talents
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Loader.Gossip
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Metadata

  @visual_spell 14_867

  def available?(%Character{unit: %{class: class, level: level}}, trainer) when is_integer(level) and level >= 10,
    do: Gossip.class_trainer?(Guid.entry(trainer), class)

  def available?(_character, _trainer), do: false

  def confirm(%State{ready: true, character: %Character{} = character} = state, trainer) do
    if valid_trainer?(character, trainer) do
      cost = ResetPrice.cost(character.internal.talent_reset, Time.now())
      Network.send_packet(%Message.SmsgGossipComplete{})
      Network.send_packet(%Message.MsgTalentWipeConfirm{trainer_guid: trainer, cost: cost})
      %{state | talent_reset_offer: %Offer{trainer_guid: trainer, cost: cost}, gossip_menu_options: []}
    else
      %{state | talent_reset_offer: nil}
    end
  end

  def confirm(state, _trainer), do: state

  def complete(
        %State{
          ready: true,
          character: %Character{} = character,
          talent_reset_offer: %Offer{trainer_guid: trainer, cost: maximum}
        } = state,
        trainer
      ) do
    state = %{state | talent_reset_offer: nil}
    now = Time.now()

    if valid_trainer?(character, trainer) and ResetPrice.cost(character.internal.talent_reset, now) <= maximum do
      reset(state, trainer, now)
    else
      state
    end
  end

  def complete(%State{} = state, _trainer), do: %{state | talent_reset_offer: nil}

  defp reset(%State{character: character} = state, trainer, now) do
    with [_ | _] <- TalentLogic.known_talent_spell_ids(character),
         {:ok, history, money} <- ResetPrice.purchase(character.internal.talent_reset, character.player.coinage, now) do
      {character, events} = Aura.remove_aura_types(character, [:feign_death], now)

      character = %{
        character
        | player: %{character.player | coinage: money},
          internal: %{character.internal | talent_reset: history}
      }

      state = %{state | character: Effects.enqueue(character, events)}
      reagents = pet_reagents(character)
      state = state |> Talents.reset() |> dismiss_pet() |> refund(reagents)
      character = Core.mark_broadcast_update(state.character)
      CharacterStore.put(character)
      Entity.trigger_spell(trainer, @visual_spell, character.object.guid)
      %{state | character: character}
    else
      [] ->
        Network.send_packet(%Message.MsgTalentWipeConfirm{})
        state

      {:error, :not_enough_money} ->
        Network.send_packet(%Message.SmsgBuyFailed{vendor_guid: 0, item_id: 0, error: :not_enough_money})
        state
    end
  end

  defp dismiss_pet(%State{character: character} = state) do
    case Companion.relationship(character) do
      %CompanionData{kind: kind, status: {:active, %EntityRef{}}} when kind in [:hunter_pet, :guardian] ->
        state = state |> CompanionOwner.suspend() |> CompanionVisibility.clear()
        if kind == :guardian, do: %{state | character: Companion.clear(state.character)}, else: state

      _ ->
        state
    end
  end

  defp pet_reagents(character) do
    case Companion.relationship(character) do
      %CompanionData{kind: kind, status: {:active, %EntityRef{spell_id: spell_id}}}
      when kind in [:hunter_pet, :guardian] ->
        case Map.get(character.internal.spellbook || %{}, spell_id) || SpellLoader.load(spell_id) do
          %Spell{reagents: reagents} -> reagents
          _ -> []
        end

      _ ->
        []
    end
  end

  defp refund(state, []), do: state

  defp refund(state, reagents) do
    case Items.store_many(state, reagents) do
      {:ok, updated} -> updated
      {:error, _reason, unchanged} -> unchanged
    end
  end

  defp valid_trainer?(character, trainer) do
    with false <- Core.dead?(character),
         false <- Enum.any?([:mod_stun, :mod_confuse, :mod_fear], &Aura.has_aura?(character, &1)),
         true <- is_nil(character.internal.taxi_flight),
         :mob <- Guid.entity_type(trainer),
         true <- available?(character, trainer),
         true <- interactable_trainer?(trainer),
         true <- Reputation.can_interact?(character, trainer),
         world = character.internal.world,
         {^world, _x, _y, _z} <- World.position(trainer),
         distance when is_number(distance) and distance <= 5.0 <- World.distance_between(character, trainer) do
      true
    else
      _ -> false
    end
  end

  defp interactable_trainer?(trainer) do
    case Metadata.query(trainer, [:alive?, :npc_flags, :in_combat, :unit_flags, :owner_guid]) do
      %{alive?: true, npc_flags: flags} = metadata when is_integer(flags) ->
        (flags &&& 0x10) != 0 and Map.get(metadata, :in_combat) != true and
          ((Map.get(metadata, :unit_flags) || 0) &&& 0x02000000) == 0 and
          Map.get(metadata, :owner_guid) in [nil, 0]

      _ ->
        false
    end
  end
end
