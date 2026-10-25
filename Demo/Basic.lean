theorem and_swap (p q : Prop) (hp : p) (hq : q) : q ∧ p := by
  constructor
  · exact hq
  · exact hp

theorem add_comm' (a b : Nat) : a + b = b + a := by
  induction a with
  | zero => simp
  | succ n ih => omega

-- Unfinished: put your cursor after `intro` and look at the goal in lean-tui.
theorem or_swap (p q : Prop) : p ∨ q → q ∨ p := by
  intro h
  cases h with
  | inl hp => exact Or.inr hp
  | inr hq => exact Or.inl hq
