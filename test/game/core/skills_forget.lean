namespace Elixir.ThistleTea.Game.Core.SkillsLawsTest
open Lynx

abbrev Entries := List (Term × Term)

def requested (ids : List Term) (q : Term) : Bool :=
  ids.any fun id => decide (Term.compareExact (Term.fuel q id) q id = .eq)

theorem list_of_proper (input : Term) (valid : «proper_list?/1» input = .ok Term.true) :
    ∃ ids, input = Term.list ids := by
  induction input using «proper_list?/1».induct with
  | case1 => exact ⟨[], rfl⟩
  | case2 head tail ih =>
    obtain ⟨xs, rfl⟩ := ih (by simpa [«proper_list?/1»] using valid)
    exact ⟨head :: xs, rfl⟩
  | case3 => simp_all [«proper_list?/1»]

theorem member_requested (ids : List Term) (q : Term) :
    Erlang.lists.«member/2» q (Term.list ids) = .ok (if requested ids q then Term.true else Term.false) := by
  induction ids with
  | nil => rfl
  | cons id ids ih =>
    by_cases same : Term.compareExact (Term.fuel q id) q id = .eq <;>
      simp [Erlang.lists.«member/2», requested, same] at ih ⊢ <;> exact ih

theorem drop_lookup (ids : List Term) (active : Entries) (q : Term) :
    ∃ kept, Elixir.Map.«drop_keys/2» (Term.list ids) (.map active) = .ok (.map kept) ∧
      Term.mapLookup kept q = (if requested ids q then none else Term.mapLookup active q) := by
  induction ids generalizing active with
  | nil => exact ⟨active, rfl, rfl⟩
  | cons id ids ih =>
    obtain ⟨kept, dropped, lookup⟩ := ih (active.filter fun e => Term.compareExact (Term.fuel id e.1) id e.1 != .eq)
    refine ⟨kept, by simpa [Term.list, Elixir.Map.«drop_keys/2», Erlang.maps.«remove/2»] using dropped, ?_⟩
    rw [lookup, Term.mapLookup_filter]
    by_cases same : Term.compareExact (Term.fuel q id) q id = .eq <;> simp [requested, same]

def bindings (pairs : Entries) : Term :=
  Term.list (pairs.map fun e => .tuple #[e.1, e.2])

theorem lookup_append (a b : Entries) (q : Term) :
    Term.mapLookup (a ++ b) q = (Term.mapLookup a q).or (Term.mapLookup b q) := by
  simp [Term.mapLookup, List.find?_append, Option.map_or]

theorem lookup_cons (id value q : Term) (rest : Entries) :
    Term.mapLookup ((id, value) :: rest) q =
      (if Term.compareExact (Term.fuel q id) q id = .eq then some value else Term.mapLookup rest q) := by
  by_cases same : Term.compareExact (Term.fuel q id) q id = .eq <;> simp [Term.mapLookup, same]

theorem take_lookup (ids : List Term) (active acc : Entries) (q : Term) :
    ∃ taken, Elixir.Map.«take/3» (Term.list ids) (.map active) (bindings acc) = .ok (.map taken) ∧
      Term.mapLookup taken q = (Term.mapLookup acc.reverse q).or
        (if requested ids q then Term.mapLookup active q else none) := by
  induction ids generalizing acc with
  | nil =>
    refine ⟨acc.reverse, ?_, by simp [requested]⟩
    cases acc <;> simp [bindings, Term.list, Elixir.Map.«take/3», Erlang.maps.«from_list/1», Term.pairList?]
  | cons id ids ih =>
    cases found : Term.mapLookup active id with
    | none =>
      obtain ⟨taken, result, lookup⟩ := ih acc
      refine ⟨taken, ?_, ?_⟩
      · simpa [Term.list, Elixir.Map.«take/3», Term.getMapKeys_single, found] using result
      · rw [lookup]
        by_cases same : Term.compareExact (Term.fuel q id) q id = .eq
        · rw [Term.mapLookup_congr same active, found]
          simp
        · simp [requested, same]
    | some v =>
      obtain ⟨taken, result, lookup⟩ := ih ((id, v) :: acc)
      refine ⟨taken, ?_, ?_⟩
      · simpa [bindings, Term.list, Elixir.Map.«take/3», Term.getMapKeys_single, found] using result
      · rw [lookup, List.reverse_cons, lookup_append, lookup_cons]
        by_cases same : Term.compareExact (Term.fuel q id) q id = .eq
        · rw [Term.mapLookup_congr same active, found]
          cases Term.mapLookup acc.reverse q <;> simp [requested, same]
        · cases Term.mapLookup acc.reverse q <;> simp [requested, same, Term.mapLookup]

end Elixir.ThistleTea.Game.Core.SkillsLawsTest
