defmodule ThistleTea.Game.Network.Message.CmsgTrainerBuySpell do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_TRAINER_BUY_SPELL

  alias ThistleTea.Game.Entity.Data.TrainerSpell
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Skills
  alias ThistleTea.Game.Entity.Logic.Trainer
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Player.Spells
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Loader.Gossip, as: GossipLoader
  alias ThistleTea.Game.World.Loader.Trainer, as: TrainerLoader

  defstruct [:trainer_guid, :spell_id]

  @impl ClientMessage
  def handle(
        %__MODULE__{trainer_guid: trainer_guid, spell_id: spell_id},
        %{ready: true, character: %Character{} = c} = state
      ) do
    entry = Guid.entry(trainer_guid)

    with true <- GossipLoader.trainer_of?(entry, c.unit.class, c.unit.race),
         %TrainerSpell{} = spell <- find_spell(entry, spell_id),
         true <- Trainer.fits_class_race?(spell, c.unit.class, c.unit.race),
         :green <- Trainer.state(spell, c.internal.spells, c.unit.level, c.player.skills),
         true <- spell.cost <= c.player.coinage do
      buy(state, c, trainer_guid, spell)
    else
      _ -> state
    end
  end

  def handle(_message, state), do: state

  @impl ClientMessage
  def from_binary(payload) do
    <<trainer_guid::little-size(64), spell_id::little-size(32)>> = payload

    %__MODULE__{
      trainer_guid: trainer_guid,
      spell_id: spell_id
    }
  end

  defp find_spell(creature_entry, teach_spell_id) do
    TrainerLoader.trainer_info(creature_entry).spells
    |> Enum.find(&(&1.teach_spell_id == teach_spell_id))
  end

  defp buy(state, c, trainer_guid, %TrainerSpell{} = spell) do
    character = %{c | player: %{c.player | coinage: c.player.coinage - spell.cost}}

    case Spells.learn(character, [spell.learned_spell_id]) do
      {:ok, character, _events} ->
        skills = Skills.learn_rank(character.player.skills, spell.skill_id, spell.skill_max)
        character = %{character | player: %{character.player | skills: skills}}
        CharacterStore.put(character)
        Spells.send_proficiencies(character)

        Network.send_packet(%Message.SmsgTrainerBuySucceeded{
          trainer_guid: trainer_guid,
          spell_id: spell.teach_spell_id
        })

        Network.send_packet(Core.update_object(character, :values))

        %{state | character: character}

      _ ->
        state
    end
  end
end
