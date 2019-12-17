theory SingleInputTransactions

imports Main Semantics

begin

fun inputsToTransactions :: "SlotInterval \<Rightarrow> Input list \<Rightarrow> Transaction list" where
"inputsToTransactions si Nil = Cons \<lparr> interval = si
                                    , inputs = Nil \<rparr> Nil" |
"inputsToTransactions si (Cons inp1 Nil) = Cons \<lparr> interval = si
                                                 , inputs = Cons inp1 Nil \<rparr> Nil" |
"inputsToTransactions si (Cons inp1 rest) = Cons \<lparr> interval = si
                                                 , inputs = Cons inp1 Nil \<rparr>
                                                 (inputsToTransactions si rest)"

fun traceListToSingleInput :: "Transaction list \<Rightarrow> Transaction list" where
"traceListToSingleInput Nil = Nil" |
"traceListToSingleInput (Cons \<lparr> interval = si
                              , inputs = inps \<rparr> rest) = inputsToTransactions si inps @ (traceListToSingleInput rest)"

lemma reductionLoopIdempotent :
  "reductionLoop env state contract wa pa = ContractQuiescent nwa npa nsta ncont \<Longrightarrow>
   reductionLoop env nsta ncont [] [] = ContractQuiescent [] [] nsta ncont"  
  apply (induction env state contract wa pa rule:reductionLoop.induct)
  subgoal for env state contract warnings payments
    apply (cases "reduceContractStep env state contract")
    apply (cases "reduceContractStep env nsta ncont")
    apply (simp add:Let_def)
    apply simp
    apply simp
    apply metis
    apply simp
    by simp
  done

lemma reduceContractUntilQuiescentIdempotent :           
  "reduceContractUntilQuiescent env state contract = ContractQuiescent wa pa nsta ncont \<Longrightarrow>
   reduceContractUntilQuiescent env nsta ncont = ContractQuiescent [] [] nsta ncont"
  apply (simp only:reduceContractUntilQuiescent.simps)
  using reductionLoopIdempotent by blast  

lemma applyAllLoopEmptyIdempotent :
  "applyAllLoop env sta cont [] a b = ApplyAllSuccess wa pa nsta ncont \<Longrightarrow>
   applyAllLoop env nsta ncont [] c d = ApplyAllSuccess c d nsta ncont"
  apply (simp only:applyAllLoop.simps[of env sta cont])
  apply (cases "reduceContractUntilQuiescent env sta cont")
  using reduceContractUntilQuiescentIdempotent apply auto[1]
  by simp

lemma applyAllLoopJustAppendsWarningsAndEffects :
  "applyAllLoop env st c list (wa @ wt) (ef @ et) = ApplyAllSuccess (wa @ nwa) (ef @ nef) fsta fcont \<Longrightarrow>
   applyAllLoop env st c list (wa2 @ wt) (ef2 @ et) = ApplyAllSuccess (wa2 @ nwa) (ef2 @ nef) fsta fcont"
  apply (induction list arbitrary: env st c wa wt ef et wa2 ef2 nwa nef)
  subgoal for env st c wa wt ef et wa2 ef2 nwa nef
    apply (simp only:applyAllLoop.simps[of env st c])
    apply (cases "reduceContractUntilQuiescent env st c")
    by simp_all
  subgoal for head tail env st c wa wt ef et wa2 ef2 nwa nef
    apply (simp only:applyAllLoop.simps[of env st c "(head # tail)"])
    apply (cases "reduceContractUntilQuiescent env st c")
    subgoal for tempWa tempEf tempState tempContract
      apply (simp only:ReduceResult.case)
      apply (subst list.case(2)[of _ _ head tail])
      apply (subst (asm) list.case(2)[of _ _ head tail])
      apply (cases "applyInput env tempState head tempContract")
      apply (metis ApplyResult.simps(4) append.assoc)
      by simp
    by simp
  done

lemma applyLoopIdempotent_base_case :
  "applyAllLoop env sta cont [] twa tef = ApplyAllSuccess wa pa nsta ncont \<Longrightarrow>
   applyAllLoop env nsta ncont t [] [] = ApplyAllSuccess nwa npa fsta fcont \<Longrightarrow>
   applyAllLoop env sta cont t twa tef = ApplyAllSuccess (wa @ nwa) (pa @ npa) fsta fcont"
  apply (simp only:applyAllLoop.simps[of env sta cont])
  apply (cases "reduceContractUntilQuiescent env sta cont")
  apply (simp only:ReduceResult.case list.case)
  apply (simp only:applyAllLoop.simps[of env nsta ncont])
  apply (cases "reduceContractUntilQuiescent env nsta ncont")
  apply (simp only:ReduceResult.case list.case)
  apply (cases t)
  apply (simp only:list.case)
  using reduceContractUntilQuiescentIdempotent apply auto[1]
  apply (simp only:list.case)
  subgoal for x11 x12 x13 x14 x11a x12a x13a x14a a list
    apply (cases "applyInput env x13a a x14a")
    apply (cases "applyInput env x13 a x14")
    apply (simp only:ApplyResult.case)
    apply (smt ApplyAllResult.inject ApplyResult.inject ReduceResult.inject append.right_neutral append_assoc applyAllLoopJustAppendsWarningsAndEffects convertReduceWarnings.simps(1) reduceContractUntilQuiescentIdempotent self_append_conv2)
    using reduceContractUntilQuiescentIdempotent apply auto[1]
    by simp
   apply simp
  by simp

lemma applyLoopIdempotent :
  "applyAllLoop env sta cont [h] [] [] = ApplyAllSuccess wa pa nsta ncont \<Longrightarrow>
   applyAllLoop env nsta ncont t [] [] = ApplyAllSuccess nwa npa fsta fcont \<Longrightarrow>
   applyAllLoop env sta cont (h # t) [] [] = ApplyAllSuccess (wa @ nwa) (pa @ npa) fsta fcont"
  apply (simp only:applyAllLoop.simps[of env sta cont])
  apply (cases "reduceContractUntilQuiescent env sta cont")
  apply (simp only:ReduceResult.case Let_def list.case)
  subgoal for x11 x12 x13 x14
    apply (cases "applyInput env x13 h x14")
    subgoal for x11a x12a x13a
      using applyLoopIdempotent_base_case by auto
    by simp
  by simp

lemma applyAllIterative :
  "applyAllInputs env sta cont [h] = ApplyAllSuccess wa pa nsta ncont \<Longrightarrow>
   applyAllInputs env nsta ncont t = ApplyAllSuccess nwa npa fsta fcont \<Longrightarrow>
   applyAllInputs env sta cont (h#t) = ApplyAllSuccess (wa @ nwa) (pa @ npa) fsta fcont"
  apply (simp only:applyAllInputs.simps)
  using applyLoopIdempotent by blast

lemma fixIntervalIdempotentThroughApplyAllInputs :
  "fixInterval inte sta1 = IntervalTrimmed env2 sta2 \<Longrightarrow>
   applyAllInputs env2 sta2 con3 inp1 = ApplyAllSuccess wa4 pa4 sta4 con4 \<Longrightarrow>
   fixInterval inte sta4 = IntervalTrimmed env2 sta4"
  sorry

lemma smallerSize_implies_different :
  "size cont1 < size cont \<Longrightarrow> cont1 \<noteq> cont"
  by blast

lemma reductionStep_only_makes_smaller :
  "contract \<noteq> ncontract \<Longrightarrow>
   reduceContractStep env state contract = Reduced warning effect newState ncontract \<Longrightarrow> size ncontract < size contract"
  apply (cases contract)
  apply simp
  apply (cases "refundOne (accounts state)")
  apply simp
  apply (simp add: case_prod_beta)
  subgoal for accountId payee token val contract
    apply (simp add:Let_def)
    apply (cases "evalValue env state val \<le> 0")
    apply (simp only:if_True Let_def)
    apply blast
    apply (simp only:if_False Let_def)
    apply (cases "giveMoney payee token (min (moneyInAccount accountId token (accounts state)) (evalValue env state val))
           (updateMoneyInAccount accountId token
             (moneyInAccount accountId token (accounts state) -
              min (moneyInAccount accountId token (accounts state)) (evalValue env state val))
             (accounts state))")
    apply simp
    done
    apply auto[1]
  subgoal for cases timeout contract
    apply simp
    apply (cases "slotInterval env")
    subgoal for low high
      apply simp
      apply (cases "high < timeout")
      apply simp_all
      apply (cases "timeout \<le> low")
      by simp_all
    done
  by (simp add:Let_def)

lemma reductionLoop_only_makes_smaller :
  "cont1 \<noteq> cont \<Longrightarrow>
   reductionLoop env state cont wa pa = ContractQuiescent nwa npa nsta cont1 \<Longrightarrow>
   size cont1 < size cont"
  apply (induction env state cont wa pa arbitrary:cont1 nwa npa nsta rule:reductionLoop.induct)
  subgoal for env state contract warnings payments cont1 nwa npa nsta
    apply (simp only:reductionLoop.simps[of env state contract warnings payments])
    apply (cases "reduceContractStep env state contract")
    subgoal for warning effect newState ncontract
      apply (simp del:reduceContractStep.simps reductionLoop.simps)
      by (metis dual_order.strict_trans reductionStep_only_makes_smaller)
    apply simp
  by simp
  done

lemma reduceContractUntilQuiescent_only_makes_smaller :
  "cont1 \<noteq> cont \<Longrightarrow>
   reduceContractUntilQuiescent env state cont = ContractQuiescent wa pa nsta cont1 \<Longrightarrow>
   size cont1 < size cont"
  apply (simp only:reduceContractUntilQuiescent.simps)
  by (simp add: reductionLoop_only_makes_smaller)

lemma applyCases_only_makes_smaller :
  "applyCases env curState input cases = Applied applyWarn newState cont1 \<Longrightarrow>
   size cont1 < size_list size cases"
  apply (induction env curState input cases rule:applyCases.induct)
  apply auto
  apply (metis ApplyResult.inject less_SucI less_add_Suc1 trans_less_add2)
  apply (metis ApplyResult.inject less_SucI less_add_Suc1 trans_less_add2)
  apply (metis ApplyResult.inject less_SucI less_add_Suc1 trans_less_add2)
  done

lemma applyInput_only_makes_smaller :
  "cont1 \<noteq> cont \<Longrightarrow>
   applyInput env curState input cont = Applied applyWarn newState cont1 \<Longrightarrow>
   size cont1 < size cont"
  apply (cases cont)
  apply simp_all
  subgoal for cases timeout contract
    by (simp add: add.commute applyCases_only_makes_smaller less_SucI trans_less_add2)
  done

lemma applyAllLoop_only_makes_smaller :
  "cont1 \<noteq> cont \<Longrightarrow>
   applyAllLoop env sta cont c wa ef = ApplyAllSuccess cwa1 pa1 sta1 cont1 \<Longrightarrow> cont1 \<noteq> cont \<Longrightarrow> size cont1 < size cont"
  apply (induction env sta cont c wa ef rule:applyAllLoop.induct)
  subgoal for env state contract inputs warnings payments
    apply (simp only:applyAllLoop.simps[of env state contract inputs warnings payments])
    apply (cases "reduceContractUntilQuiescent env state contract")
    apply (simp only:ReduceResult.case)
    subgoal for wa pa nsta cont1
      apply (cases inputs)
      apply (simp only:list.case)
      apply (simp add:reduceContractUntilQuiescent_only_makes_smaller)
      subgoal for head tail
      apply (simp only:list.case)
        apply (cases "applyInput env nsta head cont1")
        subgoal for applyWarn newState cont2
          apply (simp only:ApplyResult.case)
          by (smt applyInput_only_makes_smaller le_trans less_imp_le_nat not_le reduceContractUntilQuiescent_only_makes_smaller)
        by simp
      done
    by simp
  done

lemma applyAllInputs_only_makes_smaller :
  "applyAllInputs env sta cont c = ApplyAllSuccess cwa1 pa1 sta1 cont1 \<Longrightarrow>
   cont1 \<noteq> cont \<Longrightarrow> size cont1 < size cont"
  apply (simp only:applyAllInputs.simps)
  using applyAllLoop_only_makes_smaller by blast

lemma applyAllLoop_longer_doesnt_grow :
  "applyAllLoop env sta cont h wa pa = ApplyAllSuccess cwa1 pa1 sta1 cont1 \<Longrightarrow>
   applyAllLoop env sta cont (h @ t) wa pa = ApplyAllSuccess cwa2 pa2 sta2 cont2 \<Longrightarrow> size cont2 \<le> size cont1"
  apply (induction h arbitrary: env sta cont t wa pa cwa1 pa1 sta1 cont1 cwa2 pa2 sta2 cont2)
  subgoal for env sta cont t wa pa cwa1 pa1 sta1 cont1 cwa2 pa2 sta2 cont2
  apply (subst (asm) applyAllLoop.simps)
  apply (subst (asm) applyAllLoop.simps[of env sta cont "[] @ t"])
  apply (cases "reduceContractUntilQuiescent env sta cont")   
  apply (simp only:ReduceResult.case)
  apply (simp only:list.case append_Nil)
  subgoal for wa pa nsta ncont
    apply (cases t)
    apply (simp only:list.case)
    apply blast
    apply (simp only:list.case)
    subgoal for head tail
      apply (cases "applyInput env nsta head ncont")  
      apply (simp only:ApplyResult.case)
      apply (metis ApplyAllResult.inject applyAllLoop_only_makes_smaller applyInput_only_makes_smaller less_le_trans not_le_imp_less order.asym)
      by simp
    done
  by simp
  subgoal for hh ht env sta cont t wa pa cwa1 pa1 sta1 cont1 cwa2 pa2 sta2 cont2
  apply (subst (asm) applyAllLoop.simps[of env sta cont "(hh # ht)"])
  apply (subst (asm) applyAllLoop.simps[of env sta cont "(hh # ht) @ t"])
  apply (cases "reduceContractUntilQuiescent env sta cont")
  apply (simp only:ReduceResult.case List.append.append_Cons)
  apply (simp only:list.case)
  subgoal for wa pa nsta ncont
    apply (cases "applyInput env nsta hh ncont")
    apply (simp only:ApplyResult.case)
    by simp
  by simp
  done

lemma applyAllInputs_longer_doesnt_grow :
  "applyAllInputs env sta cont h = ApplyAllSuccess cwa1 pa1 sta1 cont1 \<Longrightarrow>
   applyAllInputs env sta cont (h @ t) = ApplyAllSuccess cwa2 pa2 sta2 cont2 \<Longrightarrow>
   size cont2 \<le> size cont1"
  apply (simp only:applyAllInputs.simps)
  by (simp add: applyAllLoop_longer_doesnt_grow)

lemma applyAllInputs_once_modified_always_modified :
  "applyAllInputs env sta cont [h] = ApplyAllSuccess cwa1 pa1 sta1 cont1 \<Longrightarrow>
   cont1 \<noteq> cont \<Longrightarrow>
   applyAllInputs env sta cont (h # t) = ApplyAllSuccess cwa2 pa2 sta2 cont2 \<Longrightarrow>
   cont2 \<noteq> cont"
  apply (rule smallerSize_implies_different)
  by (metis append_Cons append_Nil applyAllInputs.simps applyAllLoop_longer_doesnt_grow applyAllLoop_only_makes_smaller not_le)

lemma computeTransactionIterative_aux :
  "fixInterval inte osta = IntervalTrimmed env sta \<Longrightarrow>
   applyAllInputs env sta cont [h] = ApplyAllSuccess wa pa tsta ncont \<Longrightarrow>
   fixInterval inte tsta = IntervalTrimmed nenv nsta \<Longrightarrow>
   applyAllInputs nenv nsta ncont t = ApplyAllSuccess nwa npa fsta fcont \<Longrightarrow>
   applyAllInputs env sta cont (h # t) = ApplyAllSuccess (wa @ nwa) (pa @ npa) fsta fcont"
  using applyAllIterative fixIntervalIdempotentThroughApplyAllInputs by auto

lemma computeTransactionIterative_aux2 :
  "fixInterval inte sta = IntervalTrimmed fIenv1 fIsta1 \<Longrightarrow>
   applyAllInputs fIenv1 fIsta1 con [h] = ApplyAllSuccess cwa1 pa1 sta1 cont1 \<Longrightarrow>
    \<not> (cont1 = con \<and> (con \<noteq> Close \<or> accounts sta = [])) \<Longrightarrow>
   applyAllInputs fIenv1 fIsta1 con (h # t) = ApplyAllSuccess cwa3 pa3 sta3 cont3 \<Longrightarrow>
    \<not> (cont3 = con \<and> (con \<noteq> Close \<or> accounts sta = []))"
  using applyAllInputs_once_modified_always_modified by blast

lemma computeTransactionIterative :
  "computeTransaction \<lparr> interval = inte
                      , inputs = [h] \<rparr> sta cont = TransactionOutput \<lparr> txOutWarnings = wa
                                                                    , txOutPayments = pa
                                                                    , txOutState = nsta
                                                                    , txOutContract = ncont \<rparr> \<Longrightarrow>
   computeTransaction \<lparr> interval = inte
                      , inputs = t \<rparr> nsta ncont = TransactionOutput \<lparr> txOutWarnings = nwa
                                                                    , txOutPayments = npa
                                                                    , txOutState = fsta
                                                                    , txOutContract = fcont \<rparr> \<Longrightarrow>
   computeTransaction \<lparr> interval = inte
                      , inputs = h#t \<rparr> sta cont = TransactionOutput \<lparr> txOutWarnings = wa @ nwa
                                                                    , txOutPayments = pa @ npa
                                                                    , txOutState = fsta
                                                                    , txOutContract = fcont \<rparr>"
  apply (simp only:computeTransaction.simps)
  apply (cases "fixInterval (interval \<lparr>interval = inte, inputs = [h]\<rparr>) sta")
  subgoal for fIenv1 fIsta1
    apply (simp only:IntervalResult.case Let_def)
    apply (cases "applyAllInputs fIenv1 fIsta1 cont (inputs \<lparr>interval = inte, inputs = [h]\<rparr>)")
    apply (simp only:ApplyAllResult.case)
    subgoal for cwa1 pa1 sta1 con1
      apply (cases "cont = con1 \<and> (cont \<noteq> Close \<or> accounts sta = [])")
      apply simp
      apply (simp only:if_False)
      apply (cases "fixInterval (interval \<lparr>interval = inte, inputs = t\<rparr>) nsta")
      apply (simp only:IntervalResult.case Let_def)
      subgoal for fIenv2 fIsta2
        apply (cases "applyAllInputs fIenv2 fIsta2 ncont (inputs \<lparr>interval = inte, inputs = t\<rparr>)")
        apply (simp only:ApplyAllResult.case)
        subgoal for cwa2 pa2 sta2 con2
          apply (cases "ncont = con2 \<and> (ncont \<noteq> Close \<or> accounts nsta = [])")
          apply simp
          apply (simp only:if_False)
          apply (cases "fixInterval (interval \<lparr>interval = inte, inputs = h # t\<rparr>) sta")
          apply (simp only:IntervalResult.case Let_def)
          subgoal for fIenv3 fIsta3
            apply (cases "applyAllInputs fIenv3 fIsta3 cont (inputs \<lparr>interval = inte, inputs = h # t\<rparr>)")
            apply (simp only:ApplyAllResult.case)
            subgoal for cwa3 pa3 sta3 con3
              apply (cases "(cont = con3) \<and> (cont \<noteq> Close \<or> accounts sta = [])")
              apply (metis IntervalResult.inject(1) Transaction.select_convs(1) Transaction.select_convs(2) computeTransactionIterative_aux2)
              apply (simp only:if_False)
              by (metis ApplyAllResult.inject IntervalResult.inject(1) Transaction.select_convs(1) Transaction.select_convs(2) TransactionOutput.inject(1) TransactionOutputRecord.ext_inject applyAllInputs.simps applyLoopIdempotent fixIntervalIdempotentThroughApplyAllInputs)
            apply (metis (no_types, lifting) ApplyAllResult.distinct(1) IntervalResult.inject(1) Transaction.select_convs(1) Transaction.select_convs(2) TransactionOutput.inject(1) TransactionOutputRecord.ext_inject computeTransactionIterative_aux)
            by (metis (no_types, lifting) ApplyAllResult.distinct(3) IntervalResult.inject(1) Transaction.select_convs(1) Transaction.select_convs(2) TransactionOutput.inject(1) TransactionOutputRecord.ext_inject computeTransactionIterative_aux)
          by simp
        by simp_all
      by simp
    by simp_all
  by simp

theorem traceToSingleInputIsEquivalent : "playTrace sn co tral = playTrace sn co (traceListToSingleInput tral)"
      oops

end