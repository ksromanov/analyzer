open Prelude.Ana
open Analyses
open LocTraceDS
  
(* Custom exceptions for eval-function *)
exception Division_by_zero_Int
exception Division_by_zero_Float
exception Overflow_addition_Int
exception Overflow_multiplication_Int
exception Underflow_multiplication_Int
exception Underflow_subtraction_Int

(* Constants *)
let intMax = 2147483647
let intMin = -2147483648

(* Analysis framework for local traces *)
module Spec : Analyses.MCPSpec =
struct
include Analyses.DefaultSpec
module D = GraphSet

module C = Lattice.Unit 

let context fundec l =
  ()

let name () = "localTraces"

(* start state is a set of one empty graph *)
let startstate v = let g = D.empty () in let tmp = Printf.printf "Leerer Graph wird erstellt\n";D.add LocTraceGraph.empty g
in if D.is_empty tmp then tmp else tmp


let exitstate = startstate

(* Evaluates the effects of an assignment to sigmar *)
(* TODO eval needs to be checked on overflow and div by 0 --> custom exception managment could be useful *)
let eval sigOld vinfo (rval: exp) = 
  (* dummy value 
     This is used whenever an expression contains a variable that is not in sigmar (e.g. a global)
      In this case vinfo is considered to have an unknown value *)
  let nopVal = (Int((Big_int_Z.big_int_of_int (-13)), (Big_int_Z.big_int_of_int (-13)),IInt), false)

  (* returns a function which calculates [l1, u1] OP [l2, u2]*)
in let get_binop_int op ik = if not (CilType.Ikind.equal ik IInt) then (Printf.printf "This type of assignment is not supported\n"; exit 0) else 
(match op with 
| PlusA -> 
fun x1 x2 -> (match (x1,x2) with 
(Int(l1,u1,_)),(Int(l2,u2,_)) -> if (Big_int_Z.add_big_int u1 u2 > Big_int_Z.big_int_of_int intMax) then raise Overflow_addition_Int else Int(Big_int_Z.add_big_int l1 l2, Big_int_Z.add_big_int u1 u2, ik)
| _,_ -> Printf.printf "This type of assignment is not supported\n"; exit 0)
| MinusA -> 
fun x1 x2 -> (match (x1,x2) with (* Minus sollte negieren dann addieren sein, sonst inkorrekt!! *)
(Int(l1,u1,_)),(Int(l2,u2,_)) -> 
  let neg_second_lower = Big_int_Z.minus_big_int u2
in let neg_second_upper = Big_int_Z.minus_big_int l2
in if (Big_int_Z.add_big_int u1 neg_second_upper > Big_int_Z.big_int_of_int intMax) then raise Overflow_addition_Int else Int(Big_int_Z.add_big_int l1 neg_second_lower, Big_int_Z.add_big_int u1 neg_second_upper, ik)
| _,_ -> Printf.printf "This type of assignment is not supported\n"; exit 0)
| Lt -> 
  fun x1 x2 -> (match (x1,x2) with 
  | (Int(l1,u1,_)),(Int(l2,u2,_)) -> if Big_int_Z.lt_big_int u1 l2 then Int(Big_int_Z.big_int_of_int 1,Big_int_Z.big_int_of_int 1, ik) 
  else if Big_int_Z.le_big_int u2 l1 then Int(Big_int_Z.zero_big_int,Big_int_Z.zero_big_int, ik) else Int(Big_int_Z.zero_big_int,Big_int_Z.big_int_of_int 1, ik)
  | (Float(fl1,fu1,_)),(Float(fl2,fu2,_)) -> if fu1 < fl2 then Int(Big_int_Z.big_int_of_int 1,Big_int_Z.big_int_of_int 1, ik)
  else if fu2 <= fl1 then Int(Big_int_Z.zero_big_int,Big_int_Z.zero_big_int, ik) else Int(Big_int_Z.zero_big_int,Big_int_Z.big_int_of_int 1, ik)
  | _,_ -> Printf.printf "This type of assignment is not supported\n"; exit 0 )
| _ -> Printf.printf "This type of assignment is not supported\n"; exit 0)

in let get_binop_float op fk = if not (CilType.Fkind.equal fk FFloat) then (Printf.printf "This type of assignment is not supported\n"; exit 0) else
  (match op with 
  | PlusA -> 
    fun x1 x2 -> (match (x1,x2) with
    (Float(fLower1, fUpper1, _)),(Float(fLower2, fUpper2, _)) -> Float(fLower1 +. fLower2, fUpper1 +. fUpper2, fk)
    | _,_ -> Printf.printf "This type of assignment is not supported\n"; exit 0)
  | MinusA -> 
    fun x1 x2 -> (match (x1,x2) with
    (Float(fLower1, fUpper1, _)),(Float(fLower2, fUpper2, _)) -> Float(fLower1 -. fUpper2, fUpper1 -. fLower2, fk)
    | _,_ -> Printf.printf "This type of assignment is not supported\n"; exit 0)
  | _ -> Printf.printf "This type of assignment is not supported\n"; exit 0)
in
  let rec eval_helper subexp =
  (match subexp with
| Const(CInt(c, ik, _)) -> (Int (c,c, ik), true)
| Const(CReal(f, fk, _)) -> (Float (f, f, fk), true)
| Lval(Var(var), NoOffset) -> if SigmarMap.mem var sigOld then ((SigmarMap.find var sigOld), true) else (print_string "nopVal created at Lval\n";nopVal)
| AddrOf (Var(v), NoOffset) -> (Address(v), true)

(* unop expressions *)
(* for type Integer *)
| UnOp(Neg, unopExp, TInt(unopIk, _)) -> 
  (match eval_helper unopExp with (Int(l,u,_), true) ->(Int (Big_int_Z.minus_big_int u, Big_int_Z.minus_big_int l, unopIk), true)
    |(_, false) -> print_string "nopVal created at unop Neg for Int\n";nopVal
    |(_, _) -> Printf.printf "This type of assignment is not supported\n"; exit 0) 
(* for type float *)
| UnOp(Neg, unopExp, TFloat(unopFk, _)) -> 
      (match eval_helper unopExp with (Float(fLower, fUpper, _), true) -> (Float(-. fUpper,-. fLower, unopFk), true)
        | (_, false) -> print_string "nopVal created at unop Neg for Float\n";nopVal
        |(_, _) -> Printf.printf "This type of assignment is not supported\n"; exit 0)     

(* binop expressions *)
(* for type Integer *)
| BinOp(op, binopExp1, binopExp2,TInt(biopIk, _)) ->
  (match (eval_helper binopExp1, eval_helper binopExp2) with 
  | ((Int(l1,u1, ik1), true),(Int(l2,u2, ik2), true)) -> if CilType.Ikind.equal ik1 ik2 then ((get_binop_int op biopIk) (Int(l1,u1, ik1)) (Int(l2,u2, ik2)), true) else (print_string "nopVal is created at binop for int with different ikinds\n";nopVal)
  | ((Float(fLower1, fUpper1, fk1), true),(Float(fLower2, fUpper2, fk2), true)) -> if CilType.Fkind.equal fk1 fk2 then ((get_binop_int op biopIk) (Float(fLower1,fUpper1, fk1)) (Float(fLower2,fUpper2, fk2)), true) else(print_string "nopVal is created at binop for int with different fkinds\n";nopVal)
  | (_, (_,false)) -> print_string "nopVal created at binop for Integer 1";nopVal
  | ((_,false), _) -> print_string "nopVal created at binop for Integer 2";nopVal
  |(_, _) -> Printf.printf "This type of assignment is not supported\n"; exit 0) 

  (* for type Float *)
  | BinOp(op, binopExp1, binopExp2,TFloat(biopFk, _)) ->
    (match (eval_helper binopExp1, eval_helper binopExp2) with 
    | ((Float(fLower1, fUpper1, fk1), true),(Float(fLower2, fUpper2, fk2), true)) -> if CilType.Fkind.equal fk1 fk2 then ((get_binop_float op biopFk) (Float(fLower1,fUpper1, fk1)) (Float(fLower2,fUpper2, fk2)), true) else(print_string "nopVal is created at binop for int with different fkinds\n";nopVal)
    | (_, (_,false)) -> print_string "nopVal created at binop for Float 1";nopVal
  | ((_,false), _) -> print_string "nopVal created at binop for Float 2";nopVal
  |(_, _) -> Printf.printf "This type of assignment is not supported\n"; exit 0)
| _ -> Printf.printf "This type of assignment is not supported\n"; exit 0)
in let (result,success) = eval_helper rval 
in if success then SigmarMap.add vinfo result sigOld else (print_string "Sigmar has not been updated. Vinfo is removed."; SigmarMap.remove vinfo sigOld)

(* TODO output corresponding nodes in addition s.t. the edge is unique *)
let eval_catch_exceptions sigOld vinfo rval stateEdge =
try (eval sigOld vinfo rval, true) with 
Division_by_zero_Int -> print_string ("The CFG edge ["^(EdgeImpl.show stateEdge)^"] definitely contains an Integer division by zero.\n"); (SigmarMap.add vinfo Error sigOld ,false)
| Division_by_zero_Float -> print_string ("The CFG edge ["^(EdgeImpl.show stateEdge)^"] definitely contains a Float division by zero.\n"); (SigmarMap.add vinfo Error sigOld ,false)
| Overflow_addition_Int -> print_string ("The CFG edge ["^(EdgeImpl.show stateEdge)^"] definitely contains an Integer addition that overflows.\n"); (SigmarMap.add vinfo Error sigOld ,false)
| Underflow_subtraction_Int -> print_string ("The CFG edge ["^(EdgeImpl.show stateEdge)^"] definitely contains an Integer subtraction that underflows.\n"); (SigmarMap.add vinfo Error sigOld ,false)
| Overflow_multiplication_Int -> print_string ("The CFG edge ["^(EdgeImpl.show stateEdge)^"] definitely contains an Integer multiplication that overflows.\n"); (SigmarMap.add vinfo Error sigOld ,false)
| Underflow_multiplication_Int -> print_string ("The CFG edge ["^(EdgeImpl.show stateEdge)^"] definitely contains an Integer multiplication that underflows.\n"); (SigmarMap.add vinfo Error sigOld ,false)

let assign ctx (lval:lval) (rval:exp) : D.t = Printf.printf "assign wurde aufgerufen\n";
let fold_helper g set = let oldSigmar = LocalTraces.get_sigmar g ctx.prev_node
in
let myEdge, success =  match lval with (Var x, _) ->
  let evaluated,success_inner = eval_catch_exceptions oldSigmar x rval ctx.edge in 
   ({programPoint=ctx.prev_node;sigmar=oldSigmar},ctx.edge,{programPoint=ctx.node;sigmar=evaluated}), success_inner
  | _ -> Printf.printf "This type of assignment is not supported\n"; exit 0
  
in
  if success then D.add (LocalTraces.extend_by_gEdge g myEdge) set else set
in
   D.fold fold_helper ctx.local (D.empty ())
  
let branch ctx (exp:exp) (tv:bool) : D.t = Printf.printf "branch wurde aufgerufen\n";
let fold_helper g set = let oldSigmar = LocalTraces.get_sigmar g ctx.prev_node
in
let myEdge = ({programPoint=ctx.prev_node;sigmar=oldSigmar},ctx.edge,{programPoint=ctx.node;sigmar=oldSigmar})
in
  D.add (LocalTraces.extend_by_gEdge g myEdge) set 
in
   D.fold fold_helper ctx.local (D.empty ())

let body ctx (f:fundec) : D.t = Printf.printf "body wurde aufgerufen\n";
let fold_helper g set = let oldSigmar = LocalTraces.get_sigmar g ctx.prev_node
in
let myEdge = ({programPoint=ctx.prev_node;sigmar=oldSigmar},ctx.edge,{programPoint=ctx.node;sigmar=oldSigmar})
in
  D.add (LocalTraces.extend_by_gEdge g myEdge) set 
in
   D.fold fold_helper ctx.local (D.empty ())
      
let return ctx (exp:exp option) (f:fundec) : D.t = Printf.printf "return wurde aufgerufen\n";
let fold_helper g set = let oldSigmar = LocalTraces.get_sigmar g ctx.prev_node
in
let myEdge = ({programPoint=ctx.prev_node;sigmar=oldSigmar},ctx.edge,{programPoint=ctx.node;sigmar=oldSigmar})
in
  D.add (LocalTraces.extend_by_gEdge g myEdge) set 
in
   D.fold fold_helper ctx.local (D.empty ())

let special ctx (lval: lval option) (f:varinfo) (arglist:exp list) : D.t = Printf.printf "special wurde aufgerufen\n";
let fold_helper g set = let oldSigmar = LocalTraces.get_sigmar g ctx.prev_node
in
let myEdge = ({programPoint=ctx.prev_node;sigmar=oldSigmar},ctx.edge,{programPoint=ctx.node;sigmar=oldSigmar})
in
  D.add (LocalTraces.extend_by_gEdge g myEdge) set 
in
   D.fold fold_helper ctx.local (D.empty ())
    
let enter ctx (lval: lval option) (f:fundec) (args:exp list) : (D.t * D.t) list = Printf.printf "enter wurde aufgerufen\n";
let fold_helper g set = let oldSigmar = LocalTraces.get_sigmar g ctx.prev_node
in
let myEdge = ({programPoint=ctx.prev_node;sigmar=oldSigmar},ctx.edge,{programPoint=ctx.node;sigmar=oldSigmar})
in
  D.add (LocalTraces.extend_by_gEdge g myEdge) set 
in
let state =   D.fold fold_helper ctx.local (D.empty ())
in
  [ctx.local, state]  
  

  let combine ctx (lval:lval option) fexp (f:fundec) (args:exp list) fc (callee_local:D.t) : D.t = Printf.printf "combine wurde aufgerufen\n";
  let fold_helper g set = let oldSigmar = LocalTraces.get_sigmar g ctx.prev_node
in
let myEdge = ({programPoint=ctx.prev_node;sigmar=oldSigmar},ctx.edge,{programPoint=ctx.node;sigmar=oldSigmar})
in
  D.add (LocalTraces.extend_by_gEdge g myEdge) set 
in
   D.fold fold_helper ctx.local (D.empty ())

    let threadenter ctx lval f args = Printf.printf "threadenter wurde aufgerufen\n";[D.top ()]
    let threadspawn ctx lval f args fctx = Printf.printf "threadspawn wurde aufgerufen\n";ctx.local  
end

let _ =
  MCP.register_analysis (module Spec : MCPSpec)
