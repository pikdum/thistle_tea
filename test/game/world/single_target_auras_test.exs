defmodule ThistleTea.Game.World.SingleTargetAurasTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura.SingleTargetClaim
  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.World.SingleTargetAuras
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.WorldRef

  setup [:registry]

  describe "sync/5" do
    test "rejects a late application in another instance without replacing the live target", context do
      world = WorldRef.instance(33, 1)
      SpatialHash.update(:players, context.caster, world, 0.0, 0.0, 0.0)
      on_exit(fn -> SpatialHash.remove(:players, context.caster) end)
      SingleTargetAuras.sync(context.first.target_guid, self(), world, [context.first], context.server)

      SingleTargetAuras.sync(
        context.second.target_guid,
        self(),
        WorldRef.instance(33, 2),
        [context.second],
        context.server
      )

      assert_receive {:"$gen_cast", {:remove_single_target_aura, rejected, :removed}}
      assert rejected == context.second
      assert [{retained, _}] = :sys.get_state(context.server).sources[context.caster]
      assert retained == context.first
    end

    test "replaces an old target and ignores its late unregistration", context do
      %{server: server, caster: caster, first: first, second: second} = context
      publish(context, first)
      publish(context, second)
      assert_receive {:"$gen_cast", {:remove_single_target_aura, ^first, :removed}}
      SingleTargetAuras.sync(first.target_guid, self(), WorldRef.open(0), [], server)
      assert [{^second, _owner}] = :sys.get_state(server).sources[caster]
    end

    test "unchanged stale publications cannot reclaim a replaced target", context do
      publish(context, context.first)
      publish(context, context.second)
      assert_receive {:"$gen_cast", {:remove_single_target_aura, _, :removed}}
      publish(context, context.first)
      refute_receive {:"$gen_cast", {:remove_single_target_aura, _, _}}
      assert [{claim, _}] = :sys.get_state(context.server).sources[context.caster]
      assert claim == context.second
    end

    test "new applications can retake ownership while old removal is pending", context do
      publish(context, context.first)
      publish(context, context.second)
      newer = %{context.first | generation: 2}
      publish(context, newer)
      assert_receive {:"$gen_cast", {:remove_single_target_aura, old, :removed}}
      assert old == context.first
      assert_receive {:"$gen_cast", {:remove_single_target_aura, other, :removed}}
      assert other == context.second
      assert [{^newer, _}] = :sys.get_state(context.server).sources[context.caster]
    end

    test "independent spell groups and casters retain their targets", context do
      second_caster = System.unique_integer([:positive]) + 10_000_000
      Entity.register(second_caster)
      publish(context, context.first)
      other_group = %{context.second | spell_icon: 44, category: nil}
      other_caster = %{context.second | caster_guid: second_caster}
      publish(context, other_group)

      SingleTargetAuras.sync(
        context.second.target_guid,
        self(),
        WorldRef.open(0),
        [other_group, other_caster],
        context.server
      )

      refute_receive {:"$gen_cast", {:remove_single_target_aura, _, _}}
      assert length(:sys.get_state(context.server).sources[context.caster]) == 2
      assert length(:sys.get_state(context.server).sources[second_caster]) == 1
    end

    test "concurrent recipients converge on exactly one owner", context do
      targets = Enum.map(1..10, &%{context.first | target_guid: context.first.target_guid + &1})
      owner = self()

      targets
      |> Task.async_stream(fn claim ->
        SingleTargetAuras.sync(claim.target_guid, owner, WorldRef.open(0), [claim], context.server)
      end)
      |> Enum.each(fn result -> assert {:ok, :ok} = result end)

      assert [winner] = :sys.get_state(context.server).sources[context.caster]
      {winning_claim, ^owner} = winner

      removed =
        for _ <- 1..9 do
          assert_receive {:"$gen_cast", {:remove_single_target_aura, claim, :removed}}
          claim
        end

      assert MapSet.new([winning_claim | removed]) == MapSet.new(targets)
    end
  end

  describe "leave/3" do
    test "caster departure removes its outgoing auras", context do
      publish(context, context.first)
      SingleTargetAuras.leave(context.caster, self(), context.server)
      assert_receive {:"$gen_cast", {:remove_single_target_aura, claim, :removed}}
      assert claim == context.first
      assert :sys.get_state(context.server).sources == %{}
    end

    test "recipient departure unregisters claims without affecting other targets", context do
      publish(context, context.first)
      other = %{context.second | spell_icon: 44, category: nil}
      publish(context, other)
      SingleTargetAuras.leave(context.first.target_guid, self(), context.server)
      assert [{^other, _}] = :sys.get_state(context.server).sources[context.caster]
      refute_receive {:"$gen_cast", {:remove_single_target_aura, _, _}}
    end

    test "caster process exit releases auras even without graceful cleanup", context do
      caster = context.caster + 1_000_000
      parent = self()

      pid =
        spawn(fn ->
          Entity.register(caster)
          send(parent, :registered)

          receive do
            :stop -> :ok
          end
        end)

      assert_receive :registered
      claim = %{context.first | caster_guid: caster}
      publish(context, claim)
      send(pid, :stop)
      assert_receive {:"$gen_cast", {:remove_single_target_aura, ^claim, :removed}}
      refute Map.has_key?(:sys.get_state(context.server).sources, caster)
    end

    test "obsolete owners cannot clear a replacement process's claims", context do
      old_owner =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      SingleTargetAuras.sync(context.first.target_guid, old_owner, WorldRef.open(0), [context.first], context.server)
      newer = %{context.first | generation: 2}
      publish(context, newer)
      SingleTargetAuras.leave(newer.target_guid, old_owner, context.server)
      send(old_owner, :stop)
      assert [{^newer, _}] = :sys.get_state(context.server).sources[context.caster]
    end
  end

  describe "caster_died/3" do
    test "removes Hunter's Mark while other crowd control survives caster death", context do
      mark = %{context.first | stalked?: true}
      fear = %{context.second | spell_icon: 98, category: nil}
      publish(context, mark)
      publish(context, fear)
      SingleTargetAuras.caster_died(context.caster, self(), context.server)
      assert_receive {:"$gen_cast", {:remove_single_target_aura, ^mark, :death}}
      assert [{^fear, _}] = :sys.get_state(context.server).sources[context.caster]
      publish(context, mark)
      assert [{^fear, _}] = :sys.get_state(context.server).sources[context.caster]
    end
  end

  defp publish(context, claim),
    do: SingleTargetAuras.sync(claim.target_guid, self(), WorldRef.open(0), [claim], context.server)

  defp registry(_context) do
    server = start_supervised!({SingleTargetAuras, name: nil})
    caster = System.unique_integer([:positive]) + 20_000_000
    Entity.register(caster)

    first = %SingleTargetClaim{
      caster_guid: caster,
      target_guid: caster + 1,
      holder_key: {118, caster, nil, nil},
      generation: 1,
      spell_family: 3,
      spell_icon: 82,
      category: :mage_polymorph
    }

    %{server: server, caster: caster, first: first, second: %{first | target_guid: caster + 2}}
  end
end
