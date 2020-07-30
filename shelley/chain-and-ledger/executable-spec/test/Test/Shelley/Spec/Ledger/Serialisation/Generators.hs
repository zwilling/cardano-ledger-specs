{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE QuantifiedConstraints #-}
{-# LANGUAGE Rank2Types #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}

module Test.Shelley.Spec.Ledger.Serialisation.Generators (genPParams) where

import Cardano.Binary
  ( ToCBOR (..),
    toCBOR,
  )
import Cardano.Crypto.DSIGN.Class (SignedDSIGN (..), rawDeserialiseSigDSIGN, sizeSigDSIGN)
import Cardano.Crypto.DSIGN.Mock (MockDSIGN, VerKeyDSIGN (..))
import Cardano.Crypto.Hash (HashAlgorithm, hashWithSerialiser)
import qualified Cardano.Crypto.Hash as Hash
import Cardano.Slotting.Block (BlockNo (..))
import Cardano.Slotting.Slot (EpochNo (..), SlotNo (..))
import qualified Data.ByteString.Char8 as BS
import Data.Coerce (coerce)
import Data.IP (IPv4, IPv6, toIPv4, toIPv6)
import qualified Data.Map.Strict as Map (fromList)
import Data.Maybe (fromJust)
import Data.Proxy (Proxy (..))
import Data.Ratio ((%))
import Data.Sequence.Strict (StrictSeq)
import qualified Data.Sequence.Strict as StrictSeq
import Data.Word (Word64, Word8)
import Generic.Random (genericArbitraryU)
import Numeric.Natural (Natural)
import Shelley.Spec.Ledger.Address (Addr (Addr))
import Shelley.Spec.Ledger.Address.Bootstrap
  ( ChainCode (..),
    pattern BootstrapWitness,
  )
import Shelley.Spec.Ledger.BaseTypes
  ( DnsName,
    Network,
    Nonce (..),
    Port,
    StrictMaybe,
    UnitInterval,
    Url,
    mkNonceFromNumber,
    mkUnitInterval,
    textToDns,
    textToUrl,
  )
import Shelley.Spec.Ledger.BlockChain (HashHeader (..), pattern Block)
import Shelley.Spec.Ledger.Coin (Coin (Coin))
import Shelley.Spec.Ledger.Credential (Credential (..), Ptr, StakeReference)
import Shelley.Spec.Ledger.Crypto (Crypto (..))
import Shelley.Spec.Ledger.Delegation.Certificates (IndividualPoolStake (..), PoolDistr (..))
import Shelley.Spec.Ledger.EpochBoundary (BlocksMade (..), Stake (..))
import Shelley.Spec.Ledger.Keys
  ( KeyHash (KeyHash),
    VKey (VKey),
  )
import Shelley.Spec.Ledger.LedgerState
  ( AccountState,
    EpochState (..),
    OBftSlot,
    RewardUpdate,
    WitHashes (..),
    emptyRewardUpdate,
  )
import Shelley.Spec.Ledger.MetaData (MetaDataHash (..))
import Shelley.Spec.Ledger.OCert (KESPeriod (..))
import Shelley.Spec.Ledger.PParams (PParams, ProtVer)
import Shelley.Spec.Ledger.Rewards
  ( Likelihood (..),
    LogWeight (..),
    PerformanceEstimate (..),
  )
import qualified Shelley.Spec.Ledger.STS.Chain as STS
import qualified Shelley.Spec.Ledger.STS.Ppup as STS
import qualified Shelley.Spec.Ledger.STS.Prtcl as STS (PrtclState)
import qualified Shelley.Spec.Ledger.STS.Tickn as STS
import Shelley.Spec.Ledger.Scripts
  ( MultiSig (..),
    Script (..),
    ScriptHash (ScriptHash),
  )
import Shelley.Spec.Ledger.TxData
  ( MIRPot,
    PoolMetaData (PoolMetaData),
    PoolParams (PoolParams),
    RewardAcnt (RewardAcnt),
    StakePoolRelay,
    TxId (TxId),
    TxIn (TxIn),
    TxOut (TxOut),
  )
import Test.Cardano.Prelude (genBytes)
import Test.QuickCheck
  ( Arbitrary,
    arbitrary,
    genericShrink,
    listOf,
    oneof,
    shrink,
  )
import Test.QuickCheck.Hedgehog (hedgehog)
import Test.Shelley.Spec.Ledger.Address.Bootstrap
  ( genSignature,
  )
import qualified Test.Shelley.Spec.Ledger.ConcreteCryptoTypes as Mock
import Test.Shelley.Spec.Ledger.ConcreteCryptoTypes (Mock, NumDSIGN)
import Test.Shelley.Spec.Ledger.Generator.Core
  ( KeySpace (KeySpace_),
    NatNonce (..),
    geConstants,
    geKeySpace,
    ksCoreNodes,
    mkBlock,
    mkOCert,
  )
import Test.Shelley.Spec.Ledger.Generator.Presets (genEnv)
import qualified Test.Shelley.Spec.Ledger.Generator.Update as Update
import Test.Shelley.Spec.Ledger.NonTraceProperties.Generator (genStateTx, genValidStateTx)
import Test.Tasty.QuickCheck (Gen, choose, elements)

genHash :: forall a h. HashAlgorithm h => Gen (Hash.Hash h a)
genHash = mkDummyHash <$> arbitrary

mkDummyHash :: forall h a. HashAlgorithm h => Int -> Hash.Hash h a
mkDummyHash = coerce . hashWithSerialiser @h toCBOR

{-------------------------------------------------------------------------------
  Generators

  These are generators for roundtrip tests, so the generated values are not
  necessarily valid
-------------------------------------------------------------------------------}

type MockGen c = (Mock c, Arbitrary (VerKeyDSIGN (DSIGN c)))

instance
  (Mock c, NumDSIGN c) =>
  Arbitrary (Mock.Block c)
  where
  arbitrary = do
    let KeySpace_ {ksCoreNodes} = geKeySpace (genEnv p)
    prevHash <- arbitrary :: Gen (Mock.HashHeader c)
    allPoolKeys <- elements (map snd ksCoreNodes)
    txs <- arbitrary
    curSlotNo <- SlotNo <$> choose (0, 10)
    curBlockNo <- BlockNo <$> choose (0, 100)
    epochNonce <- arbitrary :: Gen Nonce
    blockNonce <- NatNonce . fromIntegral <$> choose (1, 100 :: Int)
    praosLeaderValue <- arbitrary :: Gen UnitInterval
    let kesPeriod = 1
        keyRegKesPeriod = 1
        ocert = mkOCert allPoolKeys 1 (KESPeriod kesPeriod)
    return $
      mkBlock
        prevHash
        allPoolKeys
        txs
        curSlotNo
        curBlockNo
        epochNonce
        blockNonce
        praosLeaderValue
        kesPeriod
        keyRegKesPeriod
        ocert
    where
      p :: Proxy c
      p = Proxy

instance (Mock c, NumDSIGN c) => Arbitrary (Mock.BHeader c) where
  arbitrary = do
    res <- arbitrary :: Gen (Mock.Block c)
    return $ case res of
      Block header _ -> header
      _ -> error "SerializationProperties::BHeader - failed to deconstruct header from block"

instance Arbitrary (SignedDSIGN MockDSIGN a) where
  arbitrary =
    SignedDSIGN . fromJust . rawDeserialiseSigDSIGN
      <$> hedgehog (genBytes . fromIntegral $ sizeSigDSIGN (Proxy :: Proxy MockDSIGN))

instance MockGen c => Arbitrary (Mock.BootstrapWitness c) where
  arbitrary = do
    key <- arbitrary
    sig <- genSignature
    chainCode <- ChainCode <$> arbitrary
    attributes <- arbitrary
    pure $ BootstrapWitness key sig chainCode attributes

instance Crypto c => Arbitrary (HashHeader c) where
  arbitrary = HashHeader <$> genHash

instance (Mock c, NumDSIGN c) => Arbitrary (Mock.Tx c) where
  arbitrary = do
    (_ledgerState, _steps, _txfee, tx, _lv) <- hedgehog (genStateTx (Proxy @c))
    return tx

instance Crypto c => Arbitrary (TxId c) where
  arbitrary = TxId <$> genHash

instance Crypto c => Arbitrary (TxIn c) where
  arbitrary =
    TxIn
      <$> (TxId <$> genHash)
      <*> arbitrary

instance Mock c => Arbitrary (Mock.TxOut c) where
  arbitrary = TxOut <$> arbitrary <*> arbitrary

instance Arbitrary Nonce where
  arbitrary =
    oneof
      [ return NeutralNonce,
        mkNonceFromNumber <$> choose (1, 123 :: Word64)
      ]

instance Arbitrary UnitInterval where
  arbitrary = fromJust . mkUnitInterval . (% 100) <$> choose (1, 99)

instance
  (Crypto c) =>
  Arbitrary (KeyHash a c)
  where
  arbitrary = KeyHash <$> genHash

instance Crypto c => Arbitrary (WitHashes c) where
  arbitrary = genericArbitraryU

instance Arbitrary MIRPot where
  arbitrary = genericArbitraryU

instance Arbitrary Natural where
  arbitrary = fromInteger <$> choose (0, 1000)

instance Arbitrary STS.VotingPeriod where
  arbitrary = genericArbitraryU
  shrink = genericShrink

instance Crypto c => Arbitrary (STS.PredicateFailure (Mock.PPUP c)) where
  arbitrary = genericArbitraryU
  shrink = genericShrink

instance Mock c => Arbitrary (STS.PredicateFailure (Mock.UTXO c)) where
  arbitrary = genericArbitraryU
  shrink = genericShrink

instance MockGen c => Arbitrary (STS.PredicateFailure (Mock.UTXOW c)) where
  arbitrary = genericArbitraryU
  shrink = genericShrink

instance Crypto c => Arbitrary (STS.PredicateFailure (Mock.POOL c)) where
  arbitrary = genericArbitraryU
  shrink = genericShrink

instance Mock c => Arbitrary (STS.PredicateFailure (Mock.DELPL c)) where
  arbitrary = genericArbitraryU
  shrink = genericShrink

instance Mock c => Arbitrary (STS.PredicateFailure (Mock.DELEG c)) where
  arbitrary = genericArbitraryU
  shrink = genericShrink

instance Mock c => Arbitrary (STS.PredicateFailure (Mock.DELEGS c)) where
  arbitrary = genericArbitraryU
  shrink = genericShrink

instance MockGen c => Arbitrary (STS.PredicateFailure (Mock.LEDGER c)) where
  arbitrary = genericArbitraryU
  shrink = genericShrink

instance MockGen c => Arbitrary (STS.PredicateFailure (Mock.LEDGERS c)) where
  arbitrary = genericArbitraryU
  shrink = genericShrink

instance Arbitrary Coin where
  -- Cannot be negative even though it is an 'Integer'
  arbitrary = Coin <$> choose (0, 1000)

instance Arbitrary SlotNo where
  -- Cannot be negative even though it is an 'Integer'
  arbitrary = SlotNo <$> choose (1, 100000)

instance Arbitrary EpochNo where
  -- Cannot be negative even though it is an 'Integer'
  arbitrary = EpochNo <$> choose (1, 100000)

instance Mock c => Arbitrary (Mock.Addr c) where
  arbitrary =
    oneof
      [ Addr <$> arbitrary <*> arbitrary <*> arbitrary
      -- TODO generate Byron addresses too
      -- SL.AddrBootstrap
      ]

instance Mock c => Arbitrary (StakeReference c) where
  arbitrary = genericArbitraryU
  shrink = genericShrink

instance
  ( Mock c
  ) =>
  Arbitrary (Credential r c)
  where
  arbitrary =
    oneof
      [ ScriptHashObj . ScriptHash <$> genHash,
        KeyHashObj <$> arbitrary
      ]

instance Arbitrary Ptr where
  arbitrary = genericArbitraryU
  shrink = genericShrink

instance Mock c => Arbitrary (RewardAcnt c) where
  arbitrary = RewardAcnt <$> arbitrary <*> arbitrary

instance Arbitrary Network where
  arbitrary = genericArbitraryU
  shrink = genericShrink

instance (Arbitrary (VerKeyDSIGN (DSIGN c))) => Arbitrary (VKey kd c) where
  arbitrary = VKey <$> arbitrary

instance Arbitrary (VerKeyDSIGN MockDSIGN) where
  arbitrary = VerKeyMockDSIGN <$> arbitrary

instance Arbitrary ProtVer where
  arbitrary = genericArbitraryU
  shrink = genericShrink

instance Crypto c => Arbitrary (ScriptHash c) where
  arbitrary = ScriptHash <$> genHash

instance Crypto c => Arbitrary (MetaDataHash c) where
  arbitrary = MetaDataHash <$> genHash

instance HashAlgorithm h => Arbitrary (Hash.Hash h a) where
  arbitrary = genHash

instance Arbitrary STS.TicknState where
  arbitrary = genericArbitraryU
  shrink = genericShrink

instance Crypto c => Arbitrary (STS.PrtclState c) where
  arbitrary = genericArbitraryU
  shrink = genericShrink

instance (Mock c, NumDSIGN c) => Arbitrary (Mock.LedgerState c) where
  arbitrary = do
    (_ledgerState, _steps, _txfee, _tx, ledgerState) <- hedgehog (genValidStateTx (Proxy @c))
    return ledgerState

instance (Mock c, NumDSIGN c) => Arbitrary (Mock.NewEpochState c) where
  arbitrary = genericArbitraryU
  shrink = genericShrink

instance Crypto c => Arbitrary (BlocksMade c) where
  arbitrary = BlocksMade <$> arbitrary

instance Crypto c => Arbitrary (PoolDistr c) where
  arbitrary =
    PoolDistr . Map.fromList
      <$> listOf ((,) <$> arbitrary <*> genVal)
    where
      genVal = IndividualPoolStake <$> arbitrary <*> genHash

instance (Mock c, NumDSIGN c) => Arbitrary (Mock.EpochState c) where
  arbitrary =
    EpochState
      <$> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> genPParams (Proxy @c)
      <*> genPParams (Proxy @c)
      <*> arbitrary

instance Arbitrary (RewardUpdate c) where
  arbitrary = return emptyRewardUpdate

instance Arbitrary a => Arbitrary (StrictMaybe a) where
  arbitrary = genericArbitraryU
  shrink = genericShrink

instance Crypto c => Arbitrary (OBftSlot c) where
  arbitrary = genericArbitraryU
  shrink = genericShrink

genPParams :: Mock c => proxy c -> Gen PParams
genPParams p = Update.genPParams (geConstants (genEnv p))

instance Arbitrary Likelihood where
  arbitrary = Likelihood <$> arbitrary

instance Arbitrary LogWeight where
  arbitrary = LogWeight <$> arbitrary

instance Mock c => Arbitrary (Mock.NonMyopic c) where
  arbitrary = genericArbitraryU
  shrink = genericShrink

instance Mock c => Arbitrary (Mock.SnapShot c) where
  arbitrary = genericArbitraryU
  shrink = genericShrink

instance Mock c => Arbitrary (Mock.SnapShots c) where
  arbitrary = genericArbitraryU
  shrink = genericShrink

instance Arbitrary PerformanceEstimate where
  arbitrary = PerformanceEstimate <$> arbitrary

instance Mock c => Arbitrary (Mock.Stake c) where
  arbitrary = Stake <$> arbitrary

instance Mock c => Arbitrary (PoolParams c) where
  arbitrary =
    PoolParams
      <$> arbitrary
      <*> genHash
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary

instance Arbitrary PoolMetaData where
  arbitrary = (`PoolMetaData` BS.pack "bytestring") <$> arbitrary

instance Arbitrary Url where
  arbitrary = return . fromJust $ textToUrl "text"

instance Arbitrary a => Arbitrary (StrictSeq a) where
  arbitrary = StrictSeq.toStrict <$> arbitrary
  shrink = map StrictSeq.toStrict . shrink . StrictSeq.getSeq

instance Arbitrary StakePoolRelay where
  arbitrary = genericArbitraryU
  shrink = genericShrink

instance Arbitrary Port where
  arbitrary = fromIntegral @Word8 @Port <$> arbitrary

instance Arbitrary IPv4 where
  arbitrary = pure $ toIPv4 [192, 0, 2, 1]

instance Arbitrary IPv6 where
  arbitrary = pure $ toIPv6 [0x2001, 0xDB8, 0, 0, 0, 0, 0, 1]

instance Arbitrary DnsName where
  arbitrary = pure . fromJust $ textToDns "foo.example.com"

instance Arbitrary AccountState where
  arbitrary = genericArbitraryU
  shrink = genericShrink

instance
  Mock c =>
  Arbitrary (MultiSig c)
  where
  arbitrary =
    oneof
      [ RequireSignature <$> arbitrary,
        RequireAllOf <$> arbitrary,
        RequireAnyOf <$> arbitrary,
        RequireMOf <$> arbitrary <*> arbitrary
      ]

instance
  Mock c =>
  Arbitrary (Script c)
  where
  arbitrary = MultiSigScript <$> arbitrary
