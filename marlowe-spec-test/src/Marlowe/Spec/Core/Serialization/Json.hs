{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}

module Marlowe.Spec.Core.Serialization.Json where

import Control.Applicative ((<|>))
import Control.Monad (join)
import Data.Aeson.Types (Result(..), ToJSON(..), FromJSON(..))
import Data.Aeson (object, (.=), (.:), withObject)
import qualified Data.Aeson.Types as JSON
import Data.Text as T
import Data.Proxy (Proxy(..))
import MarloweCoreJson
import GHC.Stack (HasCallStack)
import Test.Tasty (TestTree, testGroup)
import Marlowe.Spec.Interpret (Response (..), InterpretJsonRequest, exactMatch, Request (..), testResponse)
import Marlowe.Spec.TypeId (TypeId(..), HasTypeId (..))
import Test.Tasty.HUnit (Assertion, assertBool, testCase, (@?=))
import qualified SemanticsTypes as C
import QuickCheck.GenT (runGenT)
import Marlowe.Spec.Core.Arbitrary (arbitraryToken)
import Test.QuickCheck (generate)


data SerializationResponse transport
  = SerializationSuccess transport
  | UnknownType TypeId
  | SerializationError String
  deriving (Eq)

instance ToJSON (SerializationResponse JSON.Value) where
  toJSON (SerializationSuccess result) = object
    [ "serialization-success" .= result
    ]
  toJSON (UnknownType t) = object
    [ "unknown-type" .= toJSON t
    ]
  toJSON (SerializationError err) = object
    [ "serialization-error" .= JSON.String (T.pack err)
    ]

instance FromJSON (SerializationResponse JSON.Value) where
  parseJSON = withObject "SerializationResponse" $
      \v -> asSuccess v <|> asUnknownType v <|> asError v
    where
    asSuccess v = SerializationSuccess <$> v .: "serialization-success"
    asUnknownType v = UnknownType <$> v .: "unknown-type"
    asError v = SerializationError <$> v .: "serialization-error"


tests :: InterpretJsonRequest -> TestTree
tests i = testGroup "Json Serialization"
  [ testCase "Bound example" $ roundtripTest i condExample
  , valueTests i
  , observationTests i
  , invalidType i
  , tokenTest i
  ]

valueTests :: InterpretJsonRequest -> TestTree
valueTests i = testGroup "Value examples"
  [ testCase "Constant" $ roundtripTest i constantExample
  , testCase "Interval start" $ roundtripTest i intervalStartExample
  , testCase "Interval end" $ roundtripTest i intervalEndExample
  , testCase "Add" $ roundtripTest i addExample
  , testCase "Sub" $ roundtripTest i subExample
  , testCase "Mul" $ roundtripTest i mulExample
  , testCase "Div" $ roundtripTest i divExample
  , testCase "Negate" $ roundtripTest i negateExample
  -- , testCase "Choice value" $ roundtripTest i choiceValueExample
  , testCase "Use" $ roundtripTest i useValueExample
  , testCase "Cond" $ roundtripTest i condExample
  -- ,testCase "Available money" $ roundtripTest i availableMoneyExample
  , testResponse i "Invalid value"
    (TestRoundtripSerialization
      (TypeId "Core.Value" (Proxy @C.Value))
      (JSON.String "invalid value")
    )
    assertSerializationError
  ]

observationTests :: InterpretJsonRequest -> TestTree
observationTests i = testGroup "Observation examples"
  [ testCase "True" $ roundtripTest i trueExample
  , testCase "False" $ roundtripTest i falseExample
  , testCase "And" $ roundtripTest i andExample
  , testCase "Or" $ roundtripTest i orExample
  , testCase "Not" $ roundtripTest i notExample
  -- , testCase "Chose" $ roundtripTest i choseExample
  , testCase "Value GE" $ roundtripTest i valueGEExample
  , testCase "Value GT" $ roundtripTest i valueGTExample
  , testCase "Value LT" $ roundtripTest i valueLTExample
  , testCase "Value LE" $ roundtripTest i valueLEExample
  , testCase "Value EQ" $ roundtripTest i valueEQExample
  , testResponse i "Invalid observation"
    (TestRoundtripSerialization (TypeId "Core.Observation" (Proxy :: Proxy C.Observation)) (JSON.String "invalid"))
    assertSerializationError

  ]

-- TODO: Convert to property test once this task is done
-- SCP-4696 Improve thread usage
tokenTest :: InterpretJsonRequest -> TestTree
tokenTest i = testCase "Token test" $ do
  -- Any token that is randomly generated should pass the roundtrip test
  token <- join $ generate $ runGenT $ arbitraryToken i
  roundtripTest i token

invalidType :: InterpretJsonRequest -> TestTree
invalidType i = testResponse i "Invalid type"
    (TestRoundtripSerialization (TypeId "InvalidType" (Proxy :: Proxy ())) (JSON.String "invalid"))
    assertUnknownType

roundtripTest :: (HasTypeId a, ToJSON a) => InterpretJsonRequest -> a -> Assertion
roundtripTest interpret a = do
  res <- interpret serializationRequest
  successResponse @?= res
  where
  serializationRequest = TestRoundtripSerialization (getTypeId a) $ toJSON a
  successResponse = RequestResponse $ toJSON $ SerializationSuccess $ toJSON a

assertSerializationError :: HasCallStack => Response JSON.Value -> Assertion
assertSerializationError = assertBool "The serialization response should be SerializationError" . isSerializationError

isSerializationError :: Response JSON.Value -> Bool
isSerializationError (RequestResponse res) = case JSON.fromJSON res :: Result (SerializationResponse JSON.Value) of
  (Success (SerializationError _)) -> True
  _ -> False
isSerializationError _ = False

assertUnknownType :: HasCallStack => Response JSON.Value -> Assertion
assertUnknownType = assertBool "The serialization response should be UnknownType" . isUnknownType

isUnknownType :: Response JSON.Value -> Bool
isUnknownType (RequestResponse res) = case JSON.fromJSON res :: Result (SerializationResponse JSON.Value) of
  (Success (UnknownType _)) -> True
  _ -> False
isUnknownType _ = False
