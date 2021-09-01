{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wno-orphans #-}

-- | Prototypes EpochState as a data structure with ondisk, and inmemory components.
--   The inmemory components has two parts
--   1) A subset of the ondisk UTxO needed for the transactions, and
--   2) An accumuating sequence of changes needed to update the ondisk component
module Data.DeltaState where

import Data.FingerTree hiding (fromList)
import qualified Data.FingerTree as FT
import qualified Data.Map.Strict as Map
import Data.Messages
import qualified Data.Set as Set

-- =========================================================
-- Finger Trees as sequences with partial sums

-- | A (Partial k t) is Monoid made from a Pair of Monoids.
--  the first part of the Pair is the sum Monoid for Int,
--  the second part is the Delta Monoid (changes to the ondisk component)
data Partial k v = Partial Int (Delta k v)
  deriving (Show)

instance (Ord k, Exp v) => Semigroup (Partial k v) where
  (<>) (Partial n x) (Partial m y) = Partial (n + m) (x <> y)

instance (Ord k, Exp v) => Monoid (Partial k v) where
  mempty = Partial 0 mempty

-- | A sequence of (Delta k v) can be Measured by the (Partial k v) Monoid
instance (Ord k, Exp v) => Measured (Partial k v) (Delta k v) where
  measure m = (Partial 1 m)

-- | State has ondisk and inmemory parts.
data State k v = State
  { onDisk :: Map.Map k v,
    initInMemory :: Map.Map k v,
    activeInMemory :: Map.Map k v,
    blocks :: FingerTree (Partial k v) (Delta k v)
  }

-- | Set up an initial State by preloading a subset of the 'keys' from 'ondisk'
initialState :: (Ord k, Exp v) => Map.Map k v -> Set.Set k -> State k v
initialState ondisk keys = State ondisk memory memory FT.empty
  where
    memory = Set.foldl' accum Map.empty keys
    accum ans key = case Map.lookup key ondisk of
      Nothing -> ans
      Just v -> Map.insert key v ans

-- | Applies the 'blockfun' to the subset of the 'disk' state stored in 'memory' to compute
--   a set of changes 'delta', updates the state stored in 'memory' and adds the 'delta'
--   to the trace, which extends the memoized sequence of accumulating deltas.
applyBlock :: (Exp v, Ord k) => (Map.Map k v -> Delta k v) -> State k v -> State k v
applyBlock blockfun (State disk initial memory trace) = State disk initial memory2 trace2
  where
    delta = blockfun memory
    memory2 = applyMessages memory delta
    trace2 = delta <| trace

-- | Commit to a trace, by flushing the accumulated 'delta' back to 'ondisk'
commitTrace :: (Ord k, Exp v) => State k v -> Map.Map k v
commitTrace (State ondisk _ _ trace) = applyMessages ondisk messages
  where
    Partial _ messages = measure trace -- This is the final accumulated Delta

-- | Roll back the last 'n' blocks that were applied.
rollBack :: (Ord k, Exp v) => Int -> State k v -> State k v
rollBack n (State ondisk initial _ trace) =
  case split (\(Partial index _) -> index > n) trace of
    (_, trace2) -> State ondisk initial (applyMessages initial mess) trace2
      where
        Partial _ mess = measure trace2

-- =========================================================
-- Some examples

one :: (k, Message v) -> Delta k v
one (k, t) = Delta (Map.singleton k t)

actions :: [Delta Char Int]
actions =
  [ one ('c', Upsert (Plus 3)),
    one ('a', Upsert (Plus 2)),
    one ('b', Edit 3),
    one ('b', Delete),
    one ('a', Edit 2),
    one ('c', Upsert (Plus 5)),
    one ('d', Upsert (Plus 1)),
    one ('d', Delete)
  ]

timeline :: FingerTree (Partial Char Int) (Delta Char Int)
timeline = FT.fromList actions

ss :: (Ord k, Show k, Exp v, Show v) => FingerTree (Partial k v) (Delta k v) -> IO ()
ss x = case viewl x of
  EmptyL -> pure ()
  (a :< xs) ->
    case measure x of
      Partial index acc ->
        putStrLn ("index = " ++ show index ++ ", element = " ++ show a ++ ", cummulative action = " ++ show acc) >> ss xs

disp :: (Ord k, Exp v, Show k, Show v) => FingerTree (Partial k v) (Delta k v) -> IO ()
disp xs = putStrLn "" >> (ss xs)

-- the computed index "flows" from right to left, because the element at the end of the sequence was added first
-- For example, the sequence of Messages  [Upsert (+2),Edit 3,Delete,Edit 2], has this internal shape, where
-- the first line is the left most element of the sequence.
-- element = Upsert, cummulative action = (Edit 5), index = 4
-- element = (Edit 3), cummulative action = (Edit 3), index = 3
-- element = Delete, cummulative action = Delete, index = 2
-- element = (Edit 2), cummulative action = (Edit 2), index = 1

hasindex :: Int -> Partial k1 v1 -> Partial k2 v2 -> Bool
hasindex i (Partial n _) (Partial _ _) = n > i

-- | Update a particular index with 'message' at key 'k, the cumulative actions are recomputed in log time.
update :: (Ord k, Exp v) => Int -> k -> Message v -> FingerTree (Partial k v) (Delta k v) -> FingerTree (Partial k v) (Delta k v)
update i k message trace =
  case search (hasindex i) trace of
    Position left (Delta old) right -> left >< (Delta (Map.insertWith merge k message old) <| right)
    _other -> trace
