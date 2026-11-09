(declare-const x (_ BitVec 8))
(assert (bvult x #x80))
(maximize x)
(check-sat)
