defmodule ThistleTea.Game.Player.Training do
  @moduledoc """
  Trainer interaction boundary. Lists and purchases share live trainer checks
  and pure skill requirements; every purchase revalidates available slots.
  """

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.TrainerSpell
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Hostility
  alias ThistleTea.Game.Entity.Logic.Skills
  alias ThistleTea.Game.Entity.Logic.Trainer
  alias ThistleTea.Game.Entity.Server.Player, as: PlayerServer
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.SmsgTrainerList
  alias ThistleTea.Game.Player.Reputation
  alias ThistleTea.Game.Player.Spells
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.Gossip, as: GossipLoader
  alias ThistleTea.Game.World.Loader.Trainer, as: TrainerLoader
  alias ThistleTea.Game.World.Metadata

  def send_list(%{character: %Character{} = character} = state, trainer_guid) do
    if valid_trainer?(character, trainer_guid) do
      %{trainer_type: type, spells: spells} = TrainerLoader.trainer_info(Guid.entry(trainer_guid))

      Network.send_packet(%SmsgTrainerList{
        guid: trainer_guid,
        trainer_type: type,
        spells: list_spells(spells, character, trainer_guid)
      })
    end

    state
  end

  def buy(%{character: %Character{} = character} = state, trainer_guid, spell_id) do
    with true <- valid_trainer?(character, trainer_guid),
         %TrainerSpell{} = spell <- find_spell(Guid.entry(trainer_guid), spell_id),
         true <- Trainer.fits_class_race?(spell, character.unit.class, character.unit.race),
         :green <- Trainer.state(spell, character.internal.spells, character.unit.level, character.player.skills),
         price = Reputation.price(character, trainer_guid, spell.cost),
         true <- price <= character.player.coinage do
      learn(state, trainer_guid, spell, price)
    else
      _invalid -> state
    end
  end

  def valid_trainer?(%Character{} = character, guid) do
    with true <- player_available?(character),
         :mob <- Guid.entity_type(guid),
         true <- Entity.online?(guid),
         true <- interactable_trainer?(guid),
         true <- Reputation.can_interact?(character, guid),
         false <- Hostility.hostile?(character, guid),
         true <-
           GossipLoader.trainer_of?(
             Guid.entry(guid),
             character.unit.class,
             character.unit.race,
             Reputation.exalted_with?(character, guid)
           ),
         world = character.internal.world,
         {^world, _x, _y, _z} <- World.position(guid),
         distance when is_number(distance) and distance <= 5.0 <- World.distance_between(character, guid) do
      true
    else
      _invalid -> false
    end
  end

  defp player_available?(character) do
    not Core.dead?(character) and is_nil(character.internal.taxi_flight) and
      not Enum.any?([:mod_stun, :mod_confuse, :mod_fear, :mod_charm, :mod_possess], &Aura.has_aura?(character, &1))
  end

  defp interactable_trainer?(guid) do
    case Metadata.query(guid, [:alive?, :npc_flags, :in_combat, :unit_flags, :owner_guid]) do
      %{alive?: true, npc_flags: flags} = metadata when is_integer(flags) ->
        (flags &&& 0x10) != 0 and Map.get(metadata, :in_combat) != true and
          ((Map.get(metadata, :unit_flags) || 0) &&& 0x03000000) == 0 and
          Map.get(metadata, :owner_guid) in [nil, 0]

      _invalid ->
        false
    end
  end

  defp list_spells(spells, %Character{unit: unit, player: player, internal: internal} = character, guid) do
    spells
    |> Enum.filter(&Trainer.fits_class_race?(&1, unit.class, unit.race))
    |> Enum.map(fn spell ->
      %SmsgTrainerList.Spell{
        spell_id: spell.teach_spell_id,
        state: Trainer.state(spell, internal.spells, unit.level, player.skills),
        profession_slots:
          if(Trainer.first_primary_rank?(spell) and Skills.free_profession_slots(player.skills) > 0, do: 1, else: 0),
        profession_slots_required: if(Trainer.first_primary_rank?(spell), do: 1, else: 0),
        cost: Reputation.price(character, guid, spell.cost),
        req_level: spell.req_level,
        req_skill: spell.req_skill,
        req_skill_value: spell.req_skill_value,
        prev_spell_id: spell.prev_spell_id,
        req_spell_id: spell.req_spell_id
      }
    end)
  end

  defp find_spell(entry, id), do: Enum.find(TrainerLoader.trainer_info(entry).spells, &(&1.teach_spell_id == id))

  defp learn(state, trainer_guid, spell, price) do
    character = state.character
    character = %{character | player: %{character.player | coinage: character.player.coinage - price}}

    case Spells.learn_training(character, spell) do
      {:ok, character, _events} ->
        Network.send_packet(%Message.SmsgTrainerBuySucceeded{
          trainer_guid: trainer_guid,
          spell_id: spell.teach_spell_id
        })

        PlayerServer.maybe_broadcast_update(%{state | character: Core.mark_broadcast_update(character)})

      _invalid ->
        state
    end
  end
end
