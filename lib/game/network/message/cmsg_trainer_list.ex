defmodule ThistleTea.Game.Network.Message.CmsgTrainerList do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_TRAINER_LIST

  alias ThistleTea.Game.Entity.Logic.Trainer
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message.SmsgTrainerList
  alias ThistleTea.Game.World.Loader.Gossip, as: GossipLoader
  alias ThistleTea.Game.World.Loader.Trainer, as: TrainerLoader

  defstruct [:guid]

  def send_list(%{character: %Character{unit: unit, internal: internal}} = state, trainer_guid) do
    entry = Guid.entry(trainer_guid)

    if GossipLoader.trainer_of?(entry, unit.class, unit.race) do
      %{trainer_type: trainer_type, spells: spells} = TrainerLoader.trainer_info(entry)

      Network.send_packet(%Message.SmsgTrainerList{
        guid: trainer_guid,
        trainer_type: trainer_type,
        spells: list_spells(spells, unit, internal.spells)
      })
    end

    state
  end

  defp list_spells(spells, unit, known_ids) do
    spells
    |> Enum.filter(&Trainer.fits_class_race?(&1, unit.class, unit.race))
    |> Enum.map(fn spell ->
      %SmsgTrainerList.Spell{
        spell_id: spell.teach_spell_id,
        state: Trainer.state(spell, known_ids, unit.level),
        cost: spell.cost,
        req_level: spell.req_level,
        req_skill: spell.req_skill,
        req_skill_value: spell.req_skill_value,
        prev_spell_id: spell.prev_spell_id,
        req_spell_id: spell.req_spell_id
      }
    end)
  end

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid}, %{ready: true, character: %Character{}} = state) do
    send_list(state, guid)
  end

  def handle(_message, state), do: state

  @impl ClientMessage
  def from_binary(payload) do
    <<guid::little-size(64)>> = payload

    %__MODULE__{guid: guid}
  end
end
