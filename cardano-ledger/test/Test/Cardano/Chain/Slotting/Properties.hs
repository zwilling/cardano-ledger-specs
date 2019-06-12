{-# LANGUAGE TemplateHaskell #-}

module Test.Cardano.Chain.Slotting.Properties
  ( tests
  )
where

import Cardano.Prelude
import Test.Cardano.Prelude

import Data.Data (Constr, toConstr)
import Formatting (build, sformat)

import Hedgehog ((===), forAll, property, success)
import qualified Hedgehog.Gen as Gen
import Hedgehog.Internal.Property (failWith)
import qualified Hedgehog.Range as Range

import Cardano.Chain.Slotting
  ( EpochSlots(..)
  , LocalSlotIndex(..)
  , LocalSlotIndexError(..)
  , SlotCount(..)
  , SlotNumber(..)
  , addSlotNumber
  , toSlotNumber
  , localSlotIndexFromEnum
  , localSlotIndexPred
  , localSlotIndexSucc
  , localSlotIndexToEnum
  , subSlotNumber
  , fromSlotNumber
  )
import Test.Cardano.Chain.Slotting.Gen
  ( genEpochSlots
  , genSlotNumber
  , genLocalSlotIndex
  , genSlotCount
  , genEpochAndSlotCount
  , genConsistentEpochAndSlotCountEpochSlots
  )
import Test.Options (TSGroup, TSProperty, withTestsTS)


--------------------------------------------------------------------------------
-- LocalSlotIndex
--------------------------------------------------------------------------------

-- Check that `genLocalSlotIndex` does not `panic` for different values of
-- `EpochSlots`
ts_prop_genLocalSlotIndex :: TSProperty
ts_prop_genLocalSlotIndex = withTestsTS 100 . property $ do
  es  <- forAll genEpochSlots
  lsi <- forAll $ genLocalSlotIndex es
  case lsi of
    UnsafeLocalSlotIndex _ -> success

-- Check that `localSlotIndexToEnum` fails for
-- `LocalSlotIndex` values that exceed `EpochSlots`
ts_prop_localSlotIndexToEnumOverflow :: TSProperty
ts_prop_localSlotIndexToEnumOverflow = withTestsTS 100 . property $ do
  es <- forAll genEpochSlots
  let lsi = 1 + unEpochSlots es
  assertIsLeftConstr
    dummyLocSlotIndEnumOverflow
    (localSlotIndexToEnum es (fromIntegral lsi))

-- Check that `localSlotIndexToEnum` fails for
-- `LocalSlotIndex` values that are negative.
ts_prop_localSlotIndexToEnumUnderflow :: TSProperty
ts_prop_localSlotIndexToEnumUnderflow = withTestsTS 100 . property $ do
  tVal <- forAll (Gen.int (Range.constant (negate 1) minBound))
  es   <- forAll genEpochSlots
  assertIsLeftConstr dummyLocSlotIndEnumUnderflow (localSlotIndexToEnum es tVal)

-- Check that `localSlotIndexPred` does not fail
-- for allowed values of `LocalSlotIndex` and `EpochSlots`.
ts_prop_localSlotIndexPred :: TSProperty
ts_prop_localSlotIndexPred =
  withTestsTS 100
    . property
    $ do
        es  <- forAll $ Gen.filter (\x -> unEpochSlots x /= 1) genEpochSlots
        -- Filter out LocalSlotIndex = 0 and EpochSlots = 1
        -- because you can't find the predecessor of the 0th slot.
        lsi <- forAll
          $ Gen.filter (/= UnsafeLocalSlotIndex 0) (genLocalSlotIndex es)
        assertIsRight $ localSlotIndexPred es lsi

-- Check that `localSlotIndexPred` fails for
-- the lower boundary of `LocalSlotIndex`. In
-- other words, the 0th slot does not have
-- a predecessor.
ts_prop_localSlotIndexPredMinbound :: TSProperty
ts_prop_localSlotIndexPredMinbound = withTestsTS 100 . property $ do
  eSlots <- forAll genEpochSlots
  assertIsLeftConstr
    dummyLocSlotIndEnumUnderflow
    (localSlotIndexPred eSlots (UnsafeLocalSlotIndex 0))

-- Check that `localSlotIndexSucc` does not fail
-- for allowed values of `LocalSlotIndex` and `EpochSlots`.
ts_prop_localSlotIndexSucc :: TSProperty
ts_prop_localSlotIndexSucc =
  withTestsTS 100
    . property
    $ do
        es  <- forAll genEpochSlots
        -- Generate a `LocalSlotIndex` at least two less than the `EpochSlots`
        -- to avoid overflow errors as `LocalSlotIndex` starts
        -- from 0th slot.
        lsi <- forAll $ genLocalSlotIndex es
        let esPlus2 = EpochSlots $ unEpochSlots es + 2
        assertIsRight $ localSlotIndexSucc esPlus2 lsi

-- Check that `localSlotIndexSucc` fails for
-- the upper boundary of `LocalSlotIndex`. In
-- other words, the final slot does not have
-- a successor (in terms of `LocalSlotIndex`,
-- this would actually mean moving to the next epoch).
ts_prop_localSlotIndexSuccMaxbound :: TSProperty
ts_prop_localSlotIndexSuccMaxbound = withTestsTS 100 . property $ do
  es <- forAll genEpochSlots
  assertIsLeftConstr
    dummyLocSlotIndEnumOverflow
    ( localSlotIndexSucc es
    $ UnsafeLocalSlotIndex
    $ 1
    + (fromIntegral $ unEpochSlots es)
    )

-- Check that `localSlotIndexSucc . localSlotIndexPred == id`.
ts_prop_localSlotIndexSuccPredisId :: TSProperty
ts_prop_localSlotIndexSuccPredisId = withTestsTS 100 . property $ do
  es  <- forAll genEpochSlots
  lsi <- forAll
    $ Gen.filter (\x -> unLocalSlotIndex x /= 0) (genLocalSlotIndex es)
  let predSucc = localSlotIndexPred es lsi >>= localSlotIndexSucc es
  compareValueRight lsi predSucc

-- Check that `localSlotIndexPred . localSlotIndexSucc == id`.
ts_prop_localSlotIndexPredSuccisId :: TSProperty
ts_prop_localSlotIndexPredSuccisId = withTestsTS 100 . property $ do
  es  <- forAll genEpochSlots
  lsi <- forAll $ genLocalSlotIndex es
  let
    esPlus2  = EpochSlots $ unEpochSlots es + 2
    succPred = localSlotIndexSucc esPlus2 lsi >>= localSlotIndexPred esPlus2
  compareValueRight lsi succPred

-- Check that `localSlotIndexToEnum . localSlotIndexFromEnum == id`.
ts_prop_localSlotIndexToEnumFromEnum :: TSProperty
ts_prop_localSlotIndexToEnumFromEnum = withTestsTS 100 . property $ do
  sc   <- forAll genEpochSlots
  iLsi <- forAll $ genLocalSlotIndex sc
  let fLsi = localSlotIndexToEnum sc $ localSlotIndexFromEnum iLsi
  compareValueRight iLsi fLsi

-- Check that `localSlotIndexFromEnum . localSlotIndexToEnum == id`.
ts_prop_localSlotIndexFromEnumToEnum :: TSProperty
ts_prop_localSlotIndexFromEnumToEnum = withTestsTS 100 . property $ do
  sc <- forAll genEpochSlots
  let sIndex = fromIntegral $ unEpochSlots sc - 1 :: Int
  let lsi    = localSlotIndexToEnum sc sIndex
  case lsi of
    Left err ->
      withFrozenCallStack $ failWith Nothing (show $ sformat build err)
    Right lsi' -> localSlotIndexFromEnum lsi' === sIndex

--------------------------------------------------------------------------------
-- Dummy values for constructor comparison in assertIsLeftConstr tests
--------------------------------------------------------------------------------

dummyLocSlotIndEnumOverflow :: Constr
dummyLocSlotIndEnumOverflow =
  toConstr $ LocalSlotIndexEnumOverflow (EpochSlots 1) 1

dummyLocSlotIndEnumUnderflow :: Constr
dummyLocSlotIndEnumUnderflow = toConstr $ LocalSlotIndexEnumUnderflow 1

dummyLocSlotIndIndexOverflow :: Constr
dummyLocSlotIndIndexOverflow =
  toConstr $ LocalSlotIndexOverflow (EpochSlots 1) 1

--------------------------------------------------------------------------------
-- EpochAndSlotCount
--------------------------------------------------------------------------------

-- Check that `fromSlotNumber` does not panic for
-- allowed values of `EpochSlots` and `SlotNumber`.
ts_prop_fromSlotNumber :: TSProperty
ts_prop_fromSlotNumber = withTestsTS 100 . property $ do
  sc   <- forAll genEpochSlots
  fsId <- forAll $ genSlotNumber
  _    <- pure $ fromSlotNumber sc fsId
  success

-- Check that `fromSlotNumber . toSlotNumber == id`.
ts_prop_unflattenFlattenEpochAndSlotCount :: TSProperty
ts_prop_unflattenFlattenEpochAndSlotCount = withTestsTS 100 . property $ do
  (sId, sc) <- forAll genConsistentEpochAndSlotCountEpochSlots
  sId === fromSlotNumber sc (toSlotNumber sc sId)

-- Check that `genEpochAndSlotCount` does not panic for
-- allowed values of `EpochSlots`.
ts_prop_genEpochAndSlotCount :: TSProperty
ts_prop_genEpochAndSlotCount = withTestsTS 100 . property $ do
  sc <- forAll genEpochSlots
  _  <- forAll $ genEpochAndSlotCount sc
  success

-- Check that `toSlotNumber . fromSlotNumber == id`.
ts_prop_fromToSlotNumber :: TSProperty
ts_prop_fromToSlotNumber = withTestsTS 100 . property $ do
  es   <- forAll genEpochSlots
  slot <- forAll genSlotNumber
  let fromTo = toSlotNumber es $ fromSlotNumber es slot
  slot === fromTo

-- Check that `addSlotNumber` actually adds.
ts_prop_addSlotNumber :: TSProperty
ts_prop_addSlotNumber = withTestsTS 100 . property $ do
  sc <- forAll genSlotCount
  fs <- forAll genSlotNumber
  let added = fs + (SlotNumber $ unSlotCount sc)
  addSlotNumber sc fs === added

-- Check that `subSlotNumber` actually subtracts.
ts_prop_subSlotNumber :: TSProperty
ts_prop_subSlotNumber = withTestsTS 100 . property $ do
  sc <- forAll genSlotCount
  fs <- forAll genSlotNumber
  let
    sc' = SlotNumber $ unSlotCount sc
    subtracted = fs - sc'
  subSlotNumber sc fs === if fs > sc' then subtracted else SlotNumber 0

tests :: TSGroup
tests = $$discoverPropArg
