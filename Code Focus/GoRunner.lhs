
> module GoRunner where

Standard Modules

> import Debug.Trace
> import System.IO.Unsafe
> import Data.List
> import Data.List.Split
> import qualified Data.Sequence as S

My Modules

> import GoParser


COMPILER & EXECUTOR

This is where I focus on code genration and creating a virtual machine to, compile and execute my code.
I treat my input as a high level representation of Go as a data structure that I get from GoParser. 

-----------------------------------------------------------------------------------------------------

MONANDS

Define any monads needed here

State monad:

> type State 		            =  Label
>
> data ST a 		            =  S (State -> (a, State))
>
> apply        		            :: ST a -> State -> (a,State)
> apply (S f) x 	            =  f x
>
> instance Monad ST where
>    --return 		            :: a -> ST a
>    return x   	            =  S (\s -> (x,s))
>
>    --(>>=)  		            :: ST a -> (a -> ST b) -> ST b
>    st >>= f   	            = S (\s -> let (x,s') = apply st s in apply (f x) s')


Fresh function to update states

> fresh                         :: ST Label
> fresh                         = S (\s -> (s, s+1))

-----------------------------------------------------------------------------------------------------

RUNNER

Parses, then compiles, then executes a go program from a file. 

> run f                         = exec (comp (parseGo f))

-----------------------------------------------------------------------------------------------------

COMPILER

Converts program into machine code

> comp                          :: Prog -> Code
> comp p                        =  fst (apply (comp' p) (0))

Actually compiles to machine code  

> comp'                         :: Prog -> ST Code
> comp' (Main p1)               = (mainDealer p1)
> comp' (Func n vs p1)          = (functionDealer n vs p1) 
> comp' (Seqn cs)               = (sequenceDealer cs)
> comp' (Assign n e)            = return (expression e ++ [POP n])
> comp' (If c p)				= (ifDealer c p)
> comp' (IfElse c p1 p2)        = (ifElseDealer c p1 p2)
> comp' (ElseIf c p1 cs p2)     = (elseIfDealer c p1 cs p2)
> comp' (While e p3)            = (whileDealer e p3)
> comp' (Return e)              = (returnDealer e)          
> comp' (Empty)                 = return [] 
> comp' (Show e)                = return (expression e ++ [SHOW])
> comp' (CreateChan n)          = return ([CHANNEL n])
> comp' (PushToChan n e)        = return (expression e ++ [PUSHC n])
> comp' (Wait)                  = return [WAIT]
> comp' (Kill)                  = return [KILL]
> comp' (GoCall n)              = (goCallDealer n)

Deals with Expr

> expression                    :: Expr -> Code
> expression (FuncCall n es)    = (callDealer n es)
> expression (Val i)            = [PUSH i]
> expression (Var v)            = [PUSHV v]
> expression (ExprApp o x y)    = expression x ++ expression y ++ [DO o] 
> expression (CompApp o x y)    = expression x ++ expression y ++ [COMP o]
> expression (PopFromChan n)    = [POPC n]

Deal with a list of Expr

> multExpression                :: [Expr] -> Code
> multExpression []             = []
> multExpression (e:es)         = expression e ++ multExpression es           


Deals with if 

> ifDealer                      :: Expr -> Prog -> ST Code 
> ifDealer c p1                 =   do  l       <- fresh
>                                       p1code  <- comp' p1
>                                       return (expression c ++ [JUMPZ l] ++ p1code ++ [LABEL l])   

Deals with if else

> ifElseDealer                  :: Expr -> Prog -> Prog -> ST Code
> ifElseDealer c p1 p2          =   do  l1 		<- fresh
>                                       l2      <- fresh
>                                       p1code 	<- comp' p1
>                                       p2code 	<- comp' p2
>                                       return (expression c ++ [JUMPZ l1] ++ p1code ++ [JUMP l2] ++ [LABEL l1] ++ p2code ++ [LABEL l2])

Deals with else if 

> elseIfDealer                  :: Expr -> Prog -> [ElseIfCase'] -> Prog -> ST Code 
> elseIfDealer  c p1 cs p2      =   do  l1      <- fresh
>                                       l2      <- fresh
>                                       el      <- fresh
>                                       p1code  <- comp' p1
>                                       p2code  <- comp' p2
>                                       csCode  <- listCaseDealer cs el      
>                                       return (expression c ++ [JUMPZ l1] ++ p1code ++ [JUMP el] ++ [LABEL l1] ++ csCode ++ p2code ++ [LABEL el])

Deals with a list of else if cases

> listCaseDealer                :: [ElseIfCase'] -> Label -> ST Code
> listCaseDealer [] el          = return []  
> listCaseDealer (c:cs) el      =   do  cCode   <- (caseDealer c el)
>                                       csCode  <- (listCaseDealer cs el) 
>                                       return (cCode ++ csCode)

Deals with an individual else if case

> caseDealer                    :: ElseIfCase' -> Label -> ST Code
> caseDealer (Case c p1) el     =   do  l 		<- fresh
>                                       p1code 	<- comp' p1
>                                       return (expression c ++ [JUMPZ l] ++ p1code ++ [JUMP el] ++ [LABEL l])                          


Deals with While    

> whileDealer                   :: Expr -> Prog -> ST Code
> whileDealer e p               =   do  l1      <- fresh
>                                       l2      <- fresh
>                                       pcode   <- comp' p
>                                       return ([LABEL l1] ++ expression e ++ [JUMPZ l2] ++ pcode ++ [JUMP l1] ++ [LABEL l2])

Deals with Return 

> returnDealer					:: Maybe Expr -> ST Code
> returnDealer e				=   case e of
>                                       Just exp    -> return (expression exp ++ [RSTOP])    
>                                       Nothing     -> return ([STOP])       

Deals With Sequences

> sequenceDealer                :: [Prog] -> ST Code 
> sequenceDealer []             = return []
> sequenceDealer (c:cs)         =   do  head    <- comp' c
>                                       tail    <- comp' (Seqn cs)
>                                       return (head ++ tail)  

Deals with Functions, assumes that ever function contains a return will be done at parsing level

> functionDealer                :: Name -> [Name] -> Prog ->  ST Code
> functionDealer n vs p1        =   do  p1code  <- comp' p1
>                                       return ([FUNC n] ++ [ POP v | v <-(reverse vs)] ++ p1code ++ [FEND])

Deals with function call puts whatever it is ontop of the stack if there is a return statement

> callDealer                    :: Name -> [Expr] -> Code
> callDealer n []               = [CALL n] 
> callDealer n (es)             = multExpression es ++ [CALL n] 

Deals with setting up the Main function and all the code to be run

> mainDealer                    :: Prog -> ST Code
> mainDealer p1                 =   do  p1Code  <- comp' p1 
>                                       return ([MAIN] ++ p1Code ++ [END]) 

Deal with creating a new go subroutine

> goCallDealer                  :: Name -> ST Code
> goCallDealer n                = return ([GO n]) 



-----------------------------------------------------------------------------------------------------

LOW LEVEL

Now we define what we ant our high level code to compile down too, for now I define my own low
level code and create and executer for it. 

This section can either pre repleaced or used as an intermediatary for a more useful low level 
language.

This can be represented as a mini virtual machine, we will use the same vm as was used in AFP so
as to focus n high level interpritation, look to improve this later. 

> type Stack 		            = [Number]
>
> type Mem 		                = [(Name, Number)]
>   
> type Code  		            = [Inst]
> 
> data Inst  		            =  PUSH Number
>          		                    | PUSHV Name
>          		                    | POP Name
>                                   | SHOW 
>          		                    | DO ArthOp
>          		                    | COMP CompOp
>                                   | JUMP Label
>          		                    | JUMPZ Label
>          		                    | LABEL Label
>                                   | FUNC Name 
>                                   | FEND
>                                   | CALL Name                       
>                                   | STOP                      --Used for returning nothing
>                                   | RSTOP                     --Used to return a variable from a function
>                                   | MAIN
>                                   | END                       --Signifies the end of the main function 
>                                   | PUSHC Name                --Takes element from top of stack and pushes to channel
>                                   | POPC Name                 --Pops element from a channel and puts ontop of the stack
>                                   | CHANNEL Name              --Creates new channel
>                                   | WAIT
>                                   | KILL
>                                   | GO Name
>		                                deriving (Show, Eq)
> 
> type Label 		            =  Int


Data Structures needed for Concurrency

> type Channel                  = (Name, [Number])              -- basically a stack used for concurrency

> data GoRoutine                = Go Code Int Stack Mem         -- Go ec pc ls lm
>                                   deriving (Show, Eq)

Data Structure needed to use functions that return a value, don't worry about passing round Go subroutines 
as cannot start a go subroutine in a function

> type FuncParam                = ((Stack, Mem), [Channel]) 

Iniation functions

This instiates memory, buy creating a simple easy to pattern match buffer, this is not hackable or re-creatable in
programes due to parsing restrictions (I hope...) 

> instantiateMemory             :: Mem 
> instantiateMemory             = [("", Integer 0) | x <- [1..10]]


-----------------------------------------------------------------------------------------------------
 
EXECUTER 
 
Almost entirely from AFP at this stage a simple compiler for executing the code we have will update later on

This takes a list of machine code instructions and executes them.

> exec                          :: Code -> String
> exec c                        =   case ex of 
>                                       Just n  -> "Return " ++ (getNumberAsString n) 
>                                       Nothing -> ""
>                                   where
>                                       ex = exec' c c 0 [] instantiateMemory True [] (S.fromList [],0)


This is the function that actually executes the code, c is the intial code, ec is what you're executing

Variable Explanations;

c   = all the code
ec  = the current batch of code being executed
pc  = program counter
s   = stack
m   = memory 
g   = isGlobal, says whether you are workin within a function or working globally, used for memory mangement
cs  = list of channels
gs  = list of current running go subroutines
gc  = count of current process 

> exec'                         :: Code -> Code ->  Int -> Stack -> Mem -> Bool -> [Channel] -> (S.Seq GoRoutine, Int) ->  Maybe Number
> exec' c ec pc s m g cs (gs ,gc)
>                               =   case ec !! pc of 
>                                       SHOW        -> trace (getNumberAsString (head s)) (exec' c ec (pc+1) (pop s) m g ncs (ngs, ngc) ) 
>                                       MAIN        -> exec' c ec (pc+1) s m False ncs (ngs, ngc)
>                                       FUNC n      -> exec' c ec (pc+1) s m g ncs (ngs, ngc)      
>                                       PUSH n      -> exec' c ec (pc+1) (push n s) m g ncs (ngs, ngc)
>                                       PUSHV v     -> exec' c ec (pc+1) (pushv v m s) m g ncs (ngs, ngc)
>                                       POP v       -> exec' c ec (pc+1) (pop s) (assignVariable v (head s) m g) g ncs (ngs, ngc)
>                                       DO o        -> exec' c ec (pc+1) (operation o s) m g ncs (ngs, ngc)
>                                       COMP o      -> exec' c ec (pc+1) (comparison o s) m g ncs (ngs, ngc)
>                                       LABEL l     -> exec' c ec (pc+1) s m g ncs (ngs, ngc)
>                                       JUMP l      -> exec' c ec (jump c l) s m g ncs (ngs, ngc)
>                                       JUMPZ l     -> exec' c ec (jumpz c s l pc) (pop s) m g ncs (ngs, ngc)
>                                       CALL n      -> (handleCall c ec pc s m n g ncs (ngs, ngc))  
>                                       STOP        -> Nothing
>                                       END         -> Nothing
>                                       CHANNEL n   -> exec' c ec (pc+1) s m g (createChannel n cs) (ngs, ngc)
>                                       PUSHC n     -> exec' c ec (pc+1) (pop s) m g (pushChannel n cs (head s)) (ngs, ngc)
>                                       POPC n      -> exec' c ec (pc+1) (push (getHeadChannel n cs) s) m g (popChannel n cs) (ngs, ngc)
>                                       KILL        -> exec' c ec (pc+1) s m g ncs (S.fromList [], 0)
>                                       WAIT        -> if (S.null gs) then exec' c ec (pc+1) s m g ncs (S.fromList [], 0) else exec' c ec pc s m g ncs (ngs, ngc)
>                                       GO n        -> exec' c ec (pc+1) s m g ncs ((ngs S.|> (startSubRoutine c n s)),ngc)    
>                                       RSTOP       -> error "main() cannot return a value"
>                                       FEND        -> error "Compiler Error F-01"
>                                   where
>                                       con     = subRoutsHandler gs gc cs
>                                       ncs     = snd con
>                                       ngs     = fst (fst con)
>                                       ngc     = snd (fst con)
         
         
Returns the stack and memory, used for function calls to managing stack frames and make sure variables,
don't get lost. Does the same as exec' but instead returns the stack.          
        
TODO: Implement a data structure that fully represents the necessary aparamaters of a fucntion return; stack, memory, channels etc


> stackExec'                    :: Code -> Code -> Int -> Stack -> Mem -> Bool -> [Channel] -> FuncParam

> stackExec' c [] pc s m g cs   =   error "non existent function call"

> stackExec' c ec pc s m g cs   =   case ec !! pc of 
>                                       SHOW        -> trace (getNumberAsString (head s)) (stackExec' c ec (pc+1) (pop s) m  g cs)
>                                       FUNC n      -> stackExec' c ec (pc+1) s m g cs       
>                                       PUSH n      -> stackExec' c ec (pc+1) (push n s) m g cs
>                                       PUSHV v     -> stackExec' c ec (pc+1) (pushv v m s) m g cs
>                                       POP v       -> stackExec' c ec (pc+1) (pop s) (assignVariable v (head s) m g) g cs
>                                       DO o        -> stackExec' c ec (pc+1) (operation o s) m g cs
>                                       COMP o      -> stackExec' c ec (pc+1) (comparison o s) m g cs
>                                       LABEL l     -> stackExec' c ec (pc+1) s m g cs 
>                                       JUMP l      -> stackExec' c ec (jump ec l) s m g cs
>                                       JUMPZ l     -> stackExec' c ec (jumpz ec s l pc) (pop s) m g cs
>                                       CALL n      -> (handleCallReStack c ec pc s m n g cs)
>                                       PUSHC n     -> stackExec' c ec (pc+1) (pop s) m g (pushChannel n cs (head s)) 
>                                       POPC n      -> stackExec' c ec (pc+1) (push (getHeadChannel n cs) s) m g (popChannel n cs) 
>                                       RSTOP       -> ((s, m), cs) 
>                                       STOP        -> ((s, m), cs)  
>                                       FEND        -> ((s, m), cs)
>                                       CHANNEL n   -> error "Cannnot make new channel within a function must be created in main()"

        
-----------------------------------------------------------------------------------------------------

STACK FUCNTIONS

This is a series of functions that handle the stack


push onto top of stack an integer

> push                          :: Number -> Stack -> Stack
> push (n) s                    =  [n] ++ s


push variable onto top of the stack

> pushv                         :: Name ->  Mem -> Stack -> Stack
> pushv v m s                   =  push (getVariable v m) s


pop an integer from the stack and places it into memory under that variable name

> pop                           :: Stack -> Stack
> pop s                         = tail s


Perform an operation on the first two things of the stack and leave the result on top

> operation                     :: ArthOp -> Stack -> Stack
> operation o s                 =   case o of 
>                                       ADD -> push (addNumbers v2 v1) ns 
>                                       SUB -> push (subNumbers v2 v1) ns
>                                       MUL -> push (mulNumbers v2 v1) ns 
>                                       DIV -> push (divNumbers v2 v1) ns
>                                   where
>                                       v1 = head s
>                                       v2 = head (tail s)
>                                       ns = (pop (pop s))

Perform a comparison on the first two things on the stack (leave a 1 on top if true and 0 if false)

> comparison                    ::  CompOp -> Stack -> Stack
> comparison o s                =   push (comparison' o v1 v2) ns 
>                                       where
>                                           v2 = (head s)
>                                           v1 = (head (tail s))
>                                           ns = (pop (pop s))
>
> comparison'                   :: CompOp -> Number -> Number -> Number 
> comparison' o v1 v2           =   case o of
>                                       EQU		-> if isNumEqu v1 v2  then t else f    
>                                       NEQ     -> if isNumNeq v1 v2  then f else t
>                                       GEQ     -> if isNumGeq v1 v2  then t else f
>                                       LEQ     -> if isNumLeq v1 v2  then t else f
>                                       GRT     -> if isNumGrt v1 v2  then t else f
>                                       LET     -> if isNumLet v1 v2  then t else f                                       
>                                   where 
>                                       t = Integer 1
>                                       f = Integer 0          

Multiple pop, pops the required number of things

> multiplePop                   :: Stack -> Int -> Stack
> multiplePop ss 0              = ss
> multiplePop ss n              = multiplePop (pop ss) (n-1)   
 

-----------------------------------------------------------------------------------------------------
 
MEMORY FUNCTIONS

Functions that deal with memory


This function assigns an integer to a variable

> assignVariable                :: Name -> Number -> Mem -> Bool -> Mem
> assignVariable v n m g        = if g then [(v, n)] ++ (deleteVariable v m)
>                                 else localAssign v n m 

Get the variable from memory, if not assigned already just assume that variable is 0 

> getVariable                   :: Name -> Mem -> Number
> getVariable v ms            
>                               | null memV     = error ("reference to non-existent variable " ++ v) 
>                               | otherwise     = snd (head memV)
>                                   where 
>                                       memV = [ m | m <- ms, fst m == v] 


Checks that the variable isn't being reassigned and if it is deletes that variable

> deleteVariable                :: Name -> Mem -> Mem
> deleteVariable v ms           = [ m | m <- ms, fst m /= v] 

> localAssign                   :: Name -> Number -> Mem -> Mem  
> localAssign v n ms            = if (isGlobal v ms) then [(v,n)] ++ deleteVariable v ms
>                                 else deleteVariable v ms ++ [(v,n)]  

> isGlobal                      :: Name -> Mem -> Bool
> isGlobal v (("",(Integer 0)):xs) 
>                               = False
> isGlobal v (x:xs)             = if (fst x) == v then True
>                                 else (isGlobal v xs) 

 
----------------------------------------------------------------------------------------------------- 
 
JUMP FUNCTIONS

All the functions that deal with jumping arounbd our code

> jump                          ::  Code -> Int -> Int
> jump cs l                     =   case elemIndex True [ isLabel c l | c <- cs] of 
>                                       Just n      -> n
>                                       Nothing     -> 0     --Should never happen


deals with jumpz

> jumpz                         :: Code -> Stack -> Int -> Int -> Int
> jumpz c s l pc
>                               | head s == (Integer 0)     = jump c l
>                               | otherwise                 = (pc + 1)

returns true if is the label we are looking for

> isLabel                       :: Inst -> Int -> Bool
> isLabel c l                   =   case c of 
>                                       LABEL m         ->  (m == l) 
>                                       otherwise       ->  False  

stops the program, just returns memory at the moment 

> halt 							:: Mem -> Mem   
> halt m						= m 

-----------------------------------------------------------------------------------------------------

FUNCTION CALLS

These functions deal with function calls, if returns something put ontop off stack otherwise do 

> handleCall                    :: Code -> Code -> Int -> Stack -> Mem -> Name -> Bool -> [Channel] -> (S.Seq GoRoutine, Int) -> Maybe Number
> handleCall c ec pc s m n g cs (gs, gc)
>                               =   exec' c ec (pc+1) fs fm g fcs (gs, gc) 
>                                   where
>                                       fMem    = (getGlobalMemmory m ++ instantiateMemory)
>                                       fCode   = getFunction c n
>                                       fRun    = stackExec' c fCode 0 s fMem g cs   
>                                       fs      = fst (fst fRun)
>                                       fm      = updateMemory m (snd (fst fRun))
>                                       fcs     = snd fRun
                        
Returns Stack, used for nested and recursive function calls

> handleCallReStack             :: Code -> Code-> Int -> Stack -> Mem -> Name -> Bool -> [Channel] -> FuncParam
> handleCallReStack c ec pc s m n g cs 
>                               = stackExec' c ec (pc+1) fs fm g fcs 
>                                   where 
>                                       fMem    = (getGlobalMemmory m ++ instantiateMemory)
>                                       fCode   = getFunction c n
>                                       fRun    = stackExec' c fCode 0 s fMem g cs
>                                       fs      = fst (fst fRun)
>                                       fm      = updateMemory m (snd (fst fRun))
>                                       fcs     = snd fRun 

  
Searches through code and returns a function's code, ct signifies if is currently cutting the code

> getFunction                   :: Code -> Name -> Code 
> getFunction cs n              = (concat [ f | f <- fList, (head f) == (FUNC n)] ) ++ [FEND]
>                                   where 
>                                       fList = filter (not. null) (splitOneOf [END, FEND] cs) 

--------------------------------------------------------------------------------

MEMORY MANGEMENT

These series of function deal with memory mangement and handling global and local variables

Memory is split into 2 sections the first part of memory is for global variables and the rest is for local memory!  


> getGlobalMemmory              :: Mem -> Mem
> getGlobalMemmory ms           = head (splitOn instantiateMemory ms) 

> getLocalMemmory               :: Mem -> Mem
> getLocalMemmory  ms           = head (reverse (splitOn instantiateMemory ms)) 

> updateMemory                  :: Mem -> Mem -> Mem
> updateMemory os ns            = getGlobalMemmory ns ++  instantiateMemory ++ getLocalMemmory os   

--------------------------------------------------------------------------------

OUTPUTING 

This are used for the SHOW key word which needs to output what is on top of the stack

TODO: This needs to be fixed as trace is not a good way to do this

> showHead                      :: Stack -> Stack 
> showHead s                    = unsafePerformIO( do printNumber (head s)
>                                                     return (pop s))                                                   
                                                     
> printNumber                   :: Number -> IO ()
> printNumber n                 = putStrLn (getNumberAsString n)

> getNumberAsString             :: Number -> String
> getNumberAsString (Integer n) = "Int " ++ (show n) 
> getNumberAsString (Double n)  = "Double " ++ (show n) 

--------------------------------------------------------------------------------

CHANNELS

These functions deal with handling channel requests

> createChannel                 :: Name -> [Channel] -> [Channel]
> createChannel n cs            =   if doesChannelExist n cs then error ("channel " ++ n ++ " already exists") 
>                                   else ((n,[]):cs) 

Says whether a channel exists or not

> doesChannelExist              :: Name -> [Channel] -> Bool
> doesChannelExist n cs         =   case c of
>                                       [] -> False 
>                                       _  -> True
>                                   where 
>                                       c = [ c | c <- cs, fst c == n] 

Gets channel, returns an error if channel isn't found

> getChannel                    :: Name -> [Channel] -> Channel
> getChannel n cs               =   if doesChannelExist n cs then head [c | c <- cs, fst c == n]
>                                   else error ("referenced non existent channel " ++ n)                   
   
How I handle poping of a channel 

> popChannel                    :: Name -> [Channel] -> [Channel]            --doesn't maintian channel order 
> popChannel n cs               =   if (snd pc) /= [] then [(n, pop (snd pc))] ++ [c | c <- cs, fst c /= n]
>                                   else cs
>                                   where
>                                       pc = getChannel n cs 

Gets the head of a channel, if channel is empty it will return 0.

> getHeadChannel                :: Name -> [Channel] -> Number 
> getHeadChannel n cs           = if (s == []) then (Integer 0) else (head s)
>                                   where
>                                       c   = getChannel n cs
>                                       s   = snd c          

Handling pushing to a channel

> pushChannel                   :: Name -> [Channel] -> Number -> [Channel]
> pushChannel n cs v            = [(n,v:(snd pc))] ++ [c | c <- cs, fst c /= n]
>                                   where
>                                       pc = getChannel n cs


------------------------------------------------------------------------------------

GO SUBROUTINES

Sets up a new Go sub routine.

> startSubRoutine               :: Code -> Name -> Stack -> GoRoutine
> startSubRoutine cs n s        = Go code 0 [] instantiateMemory
>                                   where 
>                                       code    = getFunction cs n 




Handles running of concurrent processes, will handle one instruction at a time

gs = list of GoRoutines Running
gc = current counter for which process is running, meaning order of gs must be maintained
cs = list of channels

TODO: Implement memory and handling changes in global memory
TODO: Allow function calls


> subRoutsHandler               :: S.Seq GoRoutine -> Int -> [Channel] -> ((S.Seq GoRoutine,Int) , [Channel])  
> subRoutsHandler gs gc cs      =   if (S.null gs) then ((gs, 0), cs) 
>                                   else 
>                                       if hasEnded ng then ((rgs, ngc), ncs)
>                                       else ((ngs, ngc), ncs) 
>                                   where
>                                       ugc     = (getIndex gs gc)
>                                       i       = subRoutHandler (S.index gs ugc) ugc cs
>                                       ng      = (fst (fst i))
>                                       ngs     = (replaceGo gs ng gc)
>                                       rgs     = (removeGo gs gc)           -- removes current process 
>                                       ncs     = snd i
>                                       ngc     = snd (fst i)


Tells us if a routine is over

> hasEnded                      :: GoRoutine -> Bool
> hasEnded (Go [] 0 s m)        = True
> hasEnded  g                   = False 

Gets the index (keeps it circular)

> getIndex                      :: S.Seq GoRoutine -> Int -> Int
> getIndex gs gc                =   if (gc > maxIndex ) then 0 else gc
>                                   where 
>                                       maxIndex    = (S.length gs) - 1      

Replace a sub routine

> replaceGo                     :: S.Seq GoRoutine -> GoRoutine -> Int -> S.Seq GoRoutine
> replaceGo gs g i              = (S.update i g gs)

Remove a sub routine 

> testGo1                       = Go [SHOW] 0 [] [] 

> removeGo                      :: S.Seq GoRoutine -> Int -> S.Seq GoRoutine
> removeGo gs i                 = (S.take i gs) S.>< (S.drop (i+1) gs) 



Here is an explantion of the inputs for subRoutHandler, that uses the data structure ,Go Code Int Stack Mem ;
It is good to note here that only one step is done at a time except when a command does nothing, such as LABEL.
Context switch occurs after a jump command

ec  = executable code
pc  = the program counter 
s   = the stack
m   = local memory, handle global variables later.

> subRoutHandler                :: GoRoutine -> Int -> [Channel] -> ((GoRoutine, Int), [Channel])
> subRoutHandler (Go ec pc s m)  gc cs 
>                               = case ec !! pc of 
>                                       SHOW        -> trace (getNumberAsString (head s)) (((Go ec (pc+1) (pop s) m), gc), cs) 
>                                       FUNC n      -> subRoutHandler (Go ec (pc+1) s m)  gc cs    
>                                       PUSH n      -> (((Go ec (pc+1) (push n s) m), gc), cs)
>                                       PUSHV v     -> (((Go ec (pc+1) (pushv v m s) m), gc), cs)
>                                       POP v       -> (((Go ec (pc+1) (pop s) (assignVariable v (head s) m False)), gc), cs)
>                                       DO o        -> (((Go ec (pc+1) (operation o s) m), gc), cs)
>                                       COMP o      -> (((Go ec (pc+1) (comparison o s) m), gc), cs)
>                                       LABEL l     -> subRoutHandler (Go ec (pc+1) s m)  gc cs                                                   --jump over and do an extra command
>                                       JUMP l      -> (((Go ec (jump ec l) s m), (gc + 1)), cs)
>                                       JUMPZ l     -> (((Go ec (jumpz ec s l pc) (pop s) m), (gc + 1)), cs)
>                                       STOP        -> (((Go [] 0 s m),(gc)), cs)
>                                       FEND        -> (((Go [] 0 s m),(gc)), cs)
>                                       PUSHC n     -> (((Go ec (pc+1) (pop s) m), gc), (pushChannel n cs (head s)))
>                                       POPC n      -> (((Go ec (pc+1) (push (getHeadChannel n cs) s) m), gc), (popChannel n cs))
>                                       CHANNEL n   -> error "Cannot create channel in subroutine, must create outside of concurrent process"
>                                       RSTOP       -> error "Subroutines must be void, cannot return value" 
>                                       CALL n      -> error "Cannot call function within a subroutine"



------------------------------------------------------------------------------------

TYPE FUNCTIONS 

> getInt                        :: Number -> Int
> getInt (Integer n)            = n

> getDouble                     :: Number -> Double
> getDouble (Double n)          = n 

> isInt                         :: Number -> Bool
> isInt (Integer n)             = True
> isInt _                       = False 

> isDouble                      :: Number -> Bool
> isDouble (Double n)           = True
> isDouble _                    = False

Comparison Operations

> isNumEqu                      :: Number -> Number -> Bool
> isNumEqu x y                  | (isInt x)         = (getInt x) == (getInt y) 
>                               | otherwise         = (getDouble x) == (getDouble y)

> isNumNeq                      :: Number -> Number -> Bool
> isNumNeq x y                  | (isInt x)         = (getInt x) /= (getInt y) 
>                               | otherwise         = (getDouble x) /= (getDouble y)

> isNumGeq                      :: Number -> Number -> Bool
> isNumGeq x y                  | (isInt x)         = (getInt x) >= (getInt y) 
>                               | otherwise         = (getDouble x) >= (getDouble y)

> isNumLeq                      :: Number -> Number -> Bool
> isNumLeq x y                  | (isInt x)         = (getInt x) <= (getInt y) 
>                               | otherwise         = (getDouble x) <= (getDouble y)

> isNumGrt                      :: Number -> Number -> Bool
> isNumGrt x y                  | (isInt x)         = (getInt x) > (getInt y) 
>                               | otherwise         = (getDouble x) > (getDouble y)

> isNumLet                      :: Number -> Number -> Bool
> isNumLet x y                  | (isInt x)         = (getInt x) < (getInt y) 
>                               | otherwise         = (getDouble x) < (getDouble y)

Arthimetic opperations

> addNumbers                    :: Number -> Number -> Number   -- (x + y)
> addNumbers x y                =   if (isInt x) then Integer ((getInt x) + (getInt y)) 
>                                   else Double ((getDouble x) + (getDouble y))

> subNumbers                    :: Number -> Number -> Number   -- (x - y)
> subNumbers x y                =   if (isInt x) then Integer ((getInt x) - (getInt y))
>                                   else Double ((getDouble x) - (getDouble y)) 

Need to be carefull with divide because of how Go deals with int divison compared to haskell

> divNumbers			        :: Number -> Number -> Number   -- (x / y)
> divNumbers x y                =   if (isInt x) then (divideInt (getInt x) (getInt y))
>                                   else (divideDouble (getDouble x) (getDouble y))

> divideInt                     :: Int -> Int -> Number 
> divideInt x y                 = Integer (quot x y) 


> divideDouble                  :: Double -> Double -> Number
> divideDouble x y              = Double (x / y)

> mulNumbers                    :: Number -> Number -> Number   -- (x * y)
> mulNumbers x y                =   if (isInt x) then Integer ((getInt x) * (getInt y))
>                                   else Double ((getDouble x) * (getDouble y))

--------------------------------------------------------------------------------
