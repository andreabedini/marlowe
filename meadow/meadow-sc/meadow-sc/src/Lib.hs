{-# LANGUAGE DataKinds       #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeOperators   #-}
module Lib
    ( startApp
    , app
    ) where

import Data.Aeson
import Data.Aeson.TH
import Network.Wai
import Network.Wai.Handler.Warp
import Servant
import Control.Monad.IO.Class
import System.IO.Temp (withSystemTempDirectory)
import System.FilePath (addTrailingPathSeparator)
import Language.Haskell.Interpreter

type API = "run" :> ReqBody '[PlainText] String :> Post '[PlainText] String :<|> Raw

startApp :: IO ()
startApp = run 8080 app

app :: Application
app = serve api server

api :: Proxy API
api = Proxy

server :: Server API
server = compileWrap :<|> (serveDirectoryFileServer "static/")
  where
   compileWrap x = liftIO (compile x)

compile :: String -> IO String
compile x = do res <- withSystemTempDirectory "meadow-comp" (doCompile x)
               return res

doCompile :: String -> String -> IO String
doCompile x f = do let fp = addTrailingPathSeparator f
                   let marlowefp = (fp ++ "Marlowe.hs")
                   let mainfp = (fp ++ "MyContract.hs")
                   writeFile marlowefp marlowe_src
                   writeFile mainfp x
                   res <- runInterpreter $ do {
                              loadModules [marlowefp, mainfp];
                              setImportsQ [("MyContract", Just "Contract"), ("Marlowe", Just "Marlowe")];
                              interpret "Marlowe.prettyPrintContract $ Contract.contract" (as :: String)}
                   return (case res of
                             Right val -> "GOOD: " ++ val
                             Left err -> "BAD: " ++ (show err))

marlowe_src = "module Marlowe(Money(..), Observation(..), Contract(..), Person, Random, BlockNumber, Cash, ConcreteChoice, Timeout, IdentCC(..), IdentChoice(..), IdentPay(..), prettyPrintContract) where\n\nimport Data.List (intercalate)\n\n-- Standard library functions\n\ngroupBy                 :: (a -> a -> Bool) -> [a] -> [[a]]\ngroupBy _  []           =  []\ngroupBy eq (x:xs)       =  (x:ys) : groupBy eq zs\n                           where (ys,zs) = span (eq x) xs\n\n -- People are represented by their public keys,\n -- which in turn are given by integers.\n\ntype Key         = Int   -- Public key\ntype Person      = Key\n\n-- Block numbers and random numbers are both integers.\n \ntype Random      = Int\ntype BlockNumber = Int\n\n-- Observables are things which are recorded on the blockchain.\n--  e.g. \"a random choice\", the value of GBP/BTC exchange rate, \8230\n\n-- Question: how do we implement these things?\n--  - We assume that some mechanism exists which will ensure that the value is looked up and recorded, or \8230\n--  - \8230 we actually provide that mechanism explicitly, e.g. with inter-contract comms or transaction generation or something.\n\n-- Other observables are possible, e.g. the value of the oil price at this time.\n-- It is assumed that these would be provided in some agreed way by an oracle of some sort.\n\n-- The Observable data type represents the different sorts of observables, \8230\n\ndata Observable = Random | BlockNumber\n                    deriving (Eq)\n\nshowObservable Random = \"Random\"\nshowObservable BlockNumber = \"BlockNumber\"\n\n-- Inputs\n-- Types for cash commits, money redeems, and choices.\n--\n-- A cash commitment is an integer (should be positive integer?)\n-- Concrete values are sometimes chosen too: these are integers for the sake of this model.\n\ntype Cash     = Int\ntype ConcreteChoice = Int\n\n-- We need to put timeouts on various operations. These could be some abstract time\n-- domain, but it only really makes sense for these to be block numbers.\n\ntype Timeout = BlockNumber\n\n-- Commitments, choices and payments are all identified by identifiers.\n-- Their types are given here. In a more sophisticated model these would\n-- be generated automatically (and so uniquely); here we simply assume that \n-- they are unique.\n\nnewtype IdentCC = IdentCC Int\n               deriving (Eq)\n\nnewtype IdentChoice = IdentChoice Int\n               deriving (Eq)\n\nnewtype IdentPay = IdentPay Int\n               deriving (Eq)\n\n-- Money is a set of contract primitives that represent constants,\n-- functions, and variables that can be evaluated as an ammount\n-- of money.\n\ndata Money = AvailableMoney IdentCC |\n             AddMoney Money Money |\n             ConstMoney Cash |\n             MoneyFromChoice IdentChoice Person Money\n                    deriving (Eq)\n\nshowMoney :: Money -> String\nshowMoney (AvailableMoney (IdentCC icc)) = \"(AvailableMoney (IdentCC \" ++ show icc ++ \"))\"\nshowMoney (AddMoney m1 m2) = \"(AddMoney \" ++ showMoney m1 ++ \" \" ++ showMoney m2 ++ \")\"\nshowMoney (ConstMoney cash) = \"(ConstMoney \" ++ show cash ++ \")\"\nshowMoney (MoneyFromChoice (IdentChoice ic) p m) = \"(MoneyFromChoice (IdentChoice \" ++ show ic ++ \") \" ++ show p ++ \" \" ++ showMoney m ++ \")\"\n\n-- Representation of observations over observables and the state.\n-- Rendered into predicates by interpretObs.\n\ndata Observation =  BelowTimeout Timeout | -- are we still on time for something that expires on Timeout?\n                    AndObs Observation Observation |\n                    OrObs Observation Observation |\n                    NotObs Observation |\n                    PersonChoseThis IdentChoice Person ConcreteChoice |\n                    PersonChoseSomething IdentChoice Person |\n                    ValueGE Money Money | -- is first ammount is greater or equal than the second?\n                    TrueObs | FalseObs\n                    deriving (Eq)\n\nshowObservation :: Observation -> String\nshowObservation (BelowTimeout tim) = \"(BelowTimeout \" ++ (show tim) ++ \")\"\nshowObservation (AndObs obs1 obs2) = \"(AndObs \" ++ (showObservation obs1) ++ \" \" ++ (showObservation obs2) ++ \")\"\nshowObservation (OrObs obs1 obs2) = \"(OrObs \" ++ (showObservation obs1) ++ \" \" ++ (showObservation obs2) ++ \")\"\nshowObservation (NotObs obs) = \"(NotObs \" ++ (showObservation obs) ++ \")\"\nshowObservation (PersonChoseThis (IdentChoice ic) per cho) = \"(PersonChoseThis (IdentChoice \" ++ (show ic) ++ \") \" ++ (show per) ++ \" \" ++ (show cho) ++ \")\"\nshowObservation (PersonChoseSomething (IdentChoice ic) per) = \"(PersonChoseSomething (IdentChoice \" ++ (show ic) ++ \") \" ++ (show per) ++ \")\"\nshowObservation (ValueGE m1 m2) = \"(ValueGE \" ++ (showMoney m1) ++ \" \" ++ (showMoney m2) ++ \")\"\nshowObservation TrueObs = \"TrueObs\"\nshowObservation FalseObs = \"FalseObs\"\n \n-- The type of contracts\n\ndata Contract =\n    Null |\n    CommitCash IdentCC Person Money Timeout Timeout Contract Contract |\n    RedeemCC IdentCC Contract |\n    Pay IdentPay Person Person Money Timeout Contract |\n    Both Contract Contract |\n    Choice Observation Contract Contract |\n    When Observation Timeout Contract Contract\n               deriving (Eq)\n\nshowContract Null = \"Null\"\nshowContract (CommitCash (IdentCC idc) per mon tim1 tim2 con1 con2) = \"(CommitCash (IdentCC \" ++ (show idc) ++ \") \" ++ (show per) ++ \" \" ++ (showMoney mon) ++ \" \" ++ (show tim1) ++ \" \" ++ (show tim2) ++ \" \" ++ (showContract con1) ++ \" \" ++ (showContract con2) ++ \")\"\nshowContract (RedeemCC (IdentCC idc) con) = \"(RedeemCC (IdentCC \" ++ (show idc) ++ \") \" ++ (showContract con) ++ \")\"\nshowContract (Pay (IdentPay idp) per1 per2 mon tim con) = \"(Pay (IdentPay \" ++ (show idp) ++ \") \" ++ (show per1) ++ \" \" ++ (show per2) ++ \" \" ++ (showMoney mon) ++ \" \" ++ (show tim) ++ \" \" ++ (showContract con) ++ \")\"\nshowContract (Both con1 con2) = \"(Both \" ++ (showContract con1) ++ \" \" ++ (showContract con2) ++ \")\"\nshowContract (Choice obs con1 con2) = \"(Choice \" ++ (showObservation obs) ++ \" \" ++ (showContract con1) ++ \" \" ++ (showContract con2) ++ \")\"\nshowContract (When obs tim con1 con2) = \"(When \" ++ (showObservation obs) ++ \" \" ++ (show tim) ++ \" \" ++ (showContract con1) ++ \" \" ++ (showContract con2) ++ \")\"\n \n\n------------------------\n-- AST dependent code --\n------------------------\n\ndata ASTNode = ASTNodeC Contract\n             | ASTNodeO Observation\n             | ASTNodeM Money\n             | ASTNodeCC IdentCC\n             | ASTNodeIC IdentChoice\n             | ASTNodeIP IdentPay\n             | ASTNodeI Int\n\nlistCurryType :: ASTNode -> (String, [ASTNode])\nlistCurryType (ASTNodeM (AvailableMoney identCC))\n = (\"AvailableMoney\", [ASTNodeCC identCC])\nlistCurryType (ASTNodeM (AddMoney money1 money2))\n = (\"AddMoney\", [ASTNodeM money1, ASTNodeM money2])\nlistCurryType (ASTNodeM (ConstMoney cash))\n = (\"ConstMoney\", [ASTNodeI cash])\nlistCurryType (ASTNodeM (MoneyFromChoice identChoice person def))\n = (\"MoneyFromChoice\", [ASTNodeIC identChoice, ASTNodeI person, ASTNodeM def])\nlistCurryType (ASTNodeO (BelowTimeout timeout))\n = (\"BelowTimeout\", [ASTNodeI timeout])\nlistCurryType (ASTNodeO (AndObs observation1 observation2))\n = (\"AndObs\", [ASTNodeO observation1, ASTNodeO observation2])\nlistCurryType (ASTNodeO (OrObs observation1 observation2))\n = (\"OrObs\", [ASTNodeO observation1, ASTNodeO observation2])\nlistCurryType (ASTNodeO (NotObs observation))\n = (\"NotObs\", [ASTNodeO observation])\nlistCurryType (ASTNodeO (PersonChoseThis identChoice person concreteChoice))\n = (\"PersonChoseThis\", [ASTNodeIC identChoice, ASTNodeI person, ASTNodeI concreteChoice])\nlistCurryType (ASTNodeO (PersonChoseSomething identChoice person))\n = (\"PersonChoseSomething\", [ASTNodeIC identChoice, ASTNodeI person])\nlistCurryType (ASTNodeO (ValueGE money1 money2))\n = (\"ValueGE\", [ASTNodeM money1, ASTNodeM money2])\nlistCurryType (ASTNodeO TrueObs) = (\"TrueObs\", [])\nlistCurryType (ASTNodeO FalseObs) = (\"FalseObs\", [])\nlistCurryType (ASTNodeC Null) = (\"Null\", [])\nlistCurryType (ASTNodeC (CommitCash identCC person cash timeout1 timeout2 contract1 contract2))\n = (\"CommitCash\", [ASTNodeCC identCC, ASTNodeI person, ASTNodeM cash, ASTNodeI timeout1,\n                   ASTNodeI timeout2, ASTNodeC contract1, ASTNodeC contract2])\nlistCurryType (ASTNodeC (RedeemCC identCC contract))\n = (\"RedeemCC\", [ASTNodeCC identCC, ASTNodeC contract])\nlistCurryType (ASTNodeC (Pay identPay person1 person2 cash timeout contract))\n = (\"Pay\", [ASTNodeIP identPay, ASTNodeI person1, ASTNodeI person2,\n            ASTNodeM cash, ASTNodeI timeout, ASTNodeC contract])\nlistCurryType (ASTNodeC (Both contract1 contract2))\n = (\"Both\", [ASTNodeC contract1, ASTNodeC contract2])\nlistCurryType (ASTNodeC (Choice observation contract1 contract2))\n = (\"Choice\", [ASTNodeO observation, ASTNodeC contract1, ASTNodeC contract2])\nlistCurryType (ASTNodeC (When observation timeout contract1 contract2))\n = (\"When\", [ASTNodeO observation, ASTNodeI timeout, ASTNodeC contract1, ASTNodeC contract2])\nlistCurryType (ASTNodeCC (IdentCC int)) = (\"IdentCC\", [ASTNodeI int])\nlistCurryType (ASTNodeIC (IdentChoice int)) = (\"IdentChoice\", [ASTNodeI int])\nlistCurryType (ASTNodeIP (IdentPay int)) = (\"IdentPay\", [ASTNodeI int])\nlistCurryType (ASTNodeI int) = (show int, [])\n\nisComplex :: ASTNode -> Bool\nisComplex (ASTNodeO _) = True\nisComplex (ASTNodeC _) = True\nisComplex (ASTNodeM _) = True\nisComplex _ = False\n\n--------------------------\n-- AST independent code --\n--------------------------\n\ndata NodeType = Trivial (String, [ASTNode])\n              | Simple (String, [ASTNode])\n              | Complex (String, [ASTNode])\n\ntabulateLine :: Int -> String\ntabulateLine n = replicate n ' '\n\nclassify :: ASTNode -> NodeType\nclassify x\n  | null $ snd r = Trivial r\n  | isComplex x = Complex r\n  | otherwise = Simple r\n  where r = listCurryType x\n\nisTrivial :: NodeType -> Bool\nisTrivial (Trivial _) = True\nisTrivial _ = False\n\nnoneComplex :: NodeType -> NodeType -> Bool\nnoneComplex (Complex _) _ = False\nnoneComplex _ (Complex _)= False\nnoneComplex _ _ = True\n\n-- We assume that Simple nodes have Simple or Trivial children\nsmartPrettyPrint :: Int -> NodeType -> String\nsmartPrettyPrint _ (Trivial a) = prettyPrint 0 a\nsmartPrettyPrint _ (Simple a) = \"(\" ++ prettyPrint 0 a ++ \")\"\nsmartPrettyPrint spaces (Complex a) = \"(\" ++ prettyPrint (spaces + 1) a ++ \")\"\n\nprettyPrint :: Int -> (String, [ASTNode]) -> String\nprettyPrint _ (name, []) = name\nprettyPrint spaces (name, args) = intercalate \"\\n\" (trivialNames : map (tabulateLine newSpaces ++) others)\n  where\n    classified = map classify args\n    newSpaces = spaces + length name + 1\n    groupedClassified = groupBy noneComplex classified\n    trivialNames = unwords (name : map (smartPrettyPrint newSpaces) (head groupedClassified))\n    others = map (unwords . map (smartPrettyPrint newSpaces)) (tail groupedClassified)\n\n-------------\n-- Wrapper --\n-------------\n\nprettyPrintContract :: Contract -> String\nprettyPrintContract = prettyPrint 0 . listCurryType . ASTNodeC\n\n"
